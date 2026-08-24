import { withSupabase } from 'npm:@supabase/server@^1'
import { hash } from 'npm:bcryptjs@3.0.2'

const encoder = new TextEncoder()

const PIN_PATTERN = /^\d{4}$/
const TIME_PATTERN = /^([01]\d|2[0-3]):([0-5]\d)$/

type WorkHourInput = {
  weekday: number
  startTime: string
  endTime: string
}

function normalizeName(value: string): string {
  return value
    .normalize('NFC')
    .trim()
    .replace(/\s+/g, ' ')
}

async function hmacHex(
  secret: string,
  message: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    {
      name: 'HMAC',
      hash: 'SHA-256',
    },
    false,
    ['sign'],
  )

  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    encoder.encode(message),
  )

  return Array.from(
    new Uint8Array(signature),
  )
    .map(
      (byte) =>
        byte.toString(16).padStart(2, '0'),
    )
    .join('')
}

function timeToMinutes(value: string): number {
  const [hour, minute] =
    value.split(':').map(Number)

  return hour * 60 + minute
}

function isValidWorkHour(
  value: unknown,
): value is WorkHourInput {
  if (
    typeof value !== 'object'
    || value === null
  ) {
    return false
  }

  const item =
    value as Record<string, unknown>

  if (
    !Number.isInteger(item.weekday)
    || Number(item.weekday) < 1
    || Number(item.weekday) > 7
  ) {
    return false
  }

  if (
    typeof item.startTime !== 'string'
    || typeof item.endTime !== 'string'
    || !TIME_PATTERN.test(item.startTime)
    || !TIME_PATTERN.test(item.endTime)
  ) {
    return false
  }

  const start =
    timeToMinutes(item.startTime)

  const end =
    timeToMinutes(item.endTime)

  if (start >= end) {
    return false
  }

  if (
    start % 15 !== 0
    || end % 15 !== 0
  ) {
    return false
  }

  return true
}

function dbMessage(error: unknown): string {
  if (
    typeof error === 'object'
    && error !== null
    && 'message' in error
  ) {
    return String(
      (error as { message: unknown })
        .message,
    )
  }

  return ''
}

export default {
  fetch: withSupabase(
    {
      // JWT validation is handled explicitly below
      // through Supabase Auth getUser(token).
      auth: 'none',
    },

    async (req, ctx) => {
      if (req.method !== 'POST') {
        return Response.json(
          {
            message:
              'Method not allowed.',
          },
          {
            status: 405,
          },
        )
      }

      try {
        // ====================================================
        // AUTHENTICATE CALLER
        //
        // We intentionally do not use:
        //
        //   withSupabase({ auth: 'user' })
        //
        // because that performs local JWKS verification.
        //
        // Instead, the caller's access token is verified by
        // Supabase Auth itself.
        // ====================================================

        const authHeader =
          req.headers.get('Authorization')

        if (
          !authHeader
          || !authHeader.startsWith('Bearer ')
        ) {
          return Response.json(
            {
              message:
                '로그인이 필요합니다.',
            },
            {
              status: 401,
            },
          )
        }

        const accessToken =
          authHeader.slice(
            'Bearer '.length,
          )

        const {
          data: authUserData,
          error: authUserError,
        } =
          await ctx.supabaseAdmin.auth
            .getUser(accessToken)

        if (
          authUserError
          || !authUserData.user
        ) {
          console.error(
            'Caller token verification failed:',
            authUserError,
          )

          return Response.json(
            {
              message:
                '로그인 정보가 만료되었거나 올바르지 않습니다.',
            },
            {
              status: 401,
            },
          )
        }

        const actorId =
          authUserData.user.id


        // ====================================================
        // STAFF AUTHORIZATION
        // ====================================================

        const {
          data: actorProfile,
          error: actorError,
        } =
          await ctx.supabaseAdmin
            .from('profiles')
            .select('role, branch_id, is_active')
            .eq('id', actorId)
            .single()

        if (
          actorError
          || !actorProfile
          || ![
            'master',
            'manager',
          ].includes(actorProfile.role)
          || actorProfile.is_active !== true
        ) {
          return Response.json(
            {
              message:
                '관리자 권한이 필요합니다.',
            },
            {
              status: 403,
            },
          )
        }


        // ====================================================
        // REQUEST
        // ====================================================

        const body = await req.json()

        const name = normalizeName(
          typeof body.name === 'string'
            ? body.name
            : '',
        )

        const pin =
          typeof body.pin === 'string'
            ? body.pin
            : ''

        const branchId =
          typeof body.branchId === 'string'
            ? body.branchId.trim()
            : ''

        const workHours =
          Array.isArray(body.workHours)
            ? body.workHours
            : []


        if (
          name.length === 0
          || name.length > 100
        ) {
          return Response.json(
            {
              message:
                '선생님 이름을 확인해주세요.',
            },
            {
              status: 400,
            },
          )
        }

        if (!PIN_PATTERN.test(pin)) {
          return Response.json(
            {
              message:
                'PIN은 4자리 숫자여야 합니다.',
            },
            {
              status: 400,
            },
          )
        }

        if (branchId.length === 0) {
          return Response.json(
            {
              message:
                '지점을 선택해주세요.',
            },
            {
              status: 400,
            },
          )
        }

        if (
          actorProfile.role === 'manager'
          && (
            typeof actorProfile.branch_id !== 'string'
            || actorProfile.branch_id !== branchId
          )
        ) {
          return Response.json(
            {
              message:
                '지점 관리자는 자기 지점에만 선생님을 등록할 수 있습니다.',
            },
            {
              status: 403,
            },
          )
        }

        if (
          !workHours.every(
            isValidWorkHour,
          )
        ) {
          return Response.json(
            {
              message:
                '근무시간을 확인해주세요. 시간은 15분 단위로 설정해야 합니다.',
            },
            {
              status: 400,
            },
          )
        }


        // ====================================================
        // PIN
        // ====================================================

        const pinPepper =
          Deno.env.get('PIN_PEPPER')

        if (!pinPepper) {
          console.error(
            'PIN_PEPPER is missing.',
          )

          return Response.json(
            {
              message:
                '계정 서버 설정 오류입니다.',
            },
            {
              status: 500,
            },
          )
        }

        const pinHash =
          await hash(
            `${pin}:${pinPepper}`,
            12,
          )

        const pinFingerprint =
          await hmacHex(
            pinPepper,
            pin,
          )


        // ====================================================
        // CREATE HIDDEN AUTH IDENTITY
        // ====================================================

        const hiddenIdentity =
          crypto.randomUUID()

        const hiddenEmail =
          `${hiddenIdentity}@auth.forestring.invalid`

        const {
          data: authData,
          error: authError,
        } =
          await ctx.supabaseAdmin.auth.admin
            .createUser({
              email: hiddenEmail,
              email_confirm: true,
            })

        if (
          authError
          || !authData.user
        ) {
          console.error(
            'Auth user creation failed:',
            authError,
          )

          return Response.json(
            {
              message:
                '선생님 계정 생성에 실패했습니다.',
            },
            {
              status: 500,
            },
          )
        }

        const teacherId =
          authData.user.id


        // ====================================================
        // CREATE FORESTRING DATA
        // ====================================================

        const {
          error: dataError,
        } =
          await ctx.supabaseAdmin.rpc(
            'admin_create_teacher_account_data',
            {
              p_actor_id:
                actorId,

              p_profile_id:
                teacherId,

              p_display_name:
                name,

              p_login_name_normalized:
                name,

              p_pin_hash:
                pinHash,

              p_pin_fingerprint:
                pinFingerprint,

              p_branch_id:
                branchId,

              p_work_hours:
                workHours,
            },
          )


        if (dataError) {
          console.error(
            'Teacher DB creation failed:',
            dataError,
          )


          // Auth user creation and PostgreSQL are not part
          // of one database transaction.
          //
          // Remove the Auth identity if the DB transaction
          // fails so an orphan account is not left behind.

          const {
            error: cleanupError,
          } =
            await ctx.supabaseAdmin.auth.admin
              .deleteUser(
                teacherId,
              )

          if (cleanupError) {
            console.error(
              'CRITICAL: orphan Auth user cleanup failed:',
              teacherId,
              cleanupError,
            )
          }

          const message =
            dbMessage(dataError)

          if (
            message.includes(
              'FORESTRING_NAME_PIN_ALREADY_IN_USE',
            )
          ) {
            return Response.json(
              {
                message:
                  '같은 이름과 PIN을 사용하는 계정이 이미 존재합니다.',
              },
              {
                status: 409,
              },
            )
          }

          if (
            message.includes(
              'FORESTRING_BRANCH_NOT_FOUND',
            )
            || message.includes(
              'FORESTRING_BRANCH_REQUIRED',
            )
          ) {
            return Response.json(
              {
                message:
                  '선택한 지점을 확인해주세요.',
              },
              {
                status: 400,
              },
            )
          }

          if (
            message.includes(
              'FORESTRING_TEACHER_CREATE_FORBIDDEN',
            )
          ) {
            return Response.json(
              {
                message:
                  '선생님을 등록할 권한이 없습니다.',
              },
              {
                status: 403,
              },
            )
          }

          if (
            message.includes(
              'FORESTRING_MANAGER_BRANCH_FORBIDDEN',
            )
          ) {
            return Response.json(
              {
                message:
                  '지점 관리자는 자기 지점에만 선생님을 등록할 수 있습니다.',
              },
              {
                status: 403,
              },
            )
          }

          if (
            message.includes(
              'FORESTRING_WORK_HOURS_OVERLAP',
            )
          ) {
            return Response.json(
              {
                message:
                  '서로 겹치는 근무시간이 있습니다.',
              },
              {
                status: 400,
              },
            )
          }

          return Response.json(
            {
              message:
                '선생님 정보 저장에 실패했습니다.',
            },
            {
              status: 500,
            },
          )
        }


        return Response.json(
          {
            teacherId,
            displayName: name,
          },
          {
            status: 201,
          },
        )
      } catch (error) {
        console.error(
          'master-create-teacher failed:',
          error,
        )

        return Response.json(
          {
            message:
              '선생님 계정 생성 중 오류가 발생했습니다.',
          },
          {
            status: 500,
          },
        )
      }
    },
  ),
}
