import { withSupabase } from 'npm:@supabase/server@^1'
import { hash } from 'npm:bcryptjs@3.0.2'

const encoder = new TextEncoder()

const PIN_PATTERN = /^\d{4}$/

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

const TIME_PATTERN =
  /^([01]\d|2[0-3]):([0-5]\d)$/

type WorkHourInput = {
  weekday: number
  startTime: string
  endTime: string
}

function normalizeName(
  value: string,
): string {
  return value
    .normalize('NFC')
    .trim()
    .replace(/\s+/g, ' ')
}

async function hmacHex(
  secret: string,
  message: string,
): Promise<string> {
  const key =
    await crypto.subtle.importKey(
      'raw',
      encoder.encode(secret),
      {
        name: 'HMAC',
        hash: 'SHA-256',
      },
      false,
      ['sign'],
    )

  const signature =
    await crypto.subtle.sign(
      'HMAC',
      key,
      encoder.encode(message),
    )

  return Array.from(
    new Uint8Array(signature),
  )
    .map(
      (byte) =>
        byte
          .toString(16)
          .padStart(2, '0'),
    )
    .join('')
}

function timeToMinutes(
  value: string,
): number {
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
    value as Record<
      string,
      unknown
    >

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
    || !TIME_PATTERN.test(
      item.startTime,
    )
    || !TIME_PATTERN.test(
      item.endTime,
    )
  ) {
    return false
  }

  const start =
    timeToMinutes(
      item.startTime,
    )

  const end =
    timeToMinutes(
      item.endTime,
    )

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

function dbMessage(
  error: unknown,
): string {
  if (
    typeof error === 'object'
    && error !== null
    && 'message' in error
  ) {
    return String(
      (
        error as {
          message: unknown
        }
      ).message,
    )
  }

  return ''
}

export default {
  fetch: withSupabase(
    {
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
        // ====================================================

        const authHeader =
          req.headers.get(
            'Authorization',
          )

        if (
          !authHeader
          || !authHeader.startsWith(
            'Bearer ',
          )
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
        // EFFECTIVE ACCESS PREFLIGHT
        //
        // PostgreSQL remains the canonical policy source.
        // The final mutation RPC checks effective access again.
        // ====================================================

        const {
          error: effectiveActorError,
        } =
          await (ctx.supabaseAdmin as any).rpc(
            'admin_get_effective_actor_context',
            {
              p_actor_id:
                actorId,
            },
          )

        if (effectiveActorError) {
          const message =
            dbMessage(effectiveActorError)

          if (
            message.includes(
              'FORESTRING_EFFECTIVE_ACCESS_REQUIRED',
            )
          ) {
            return Response.json(
              {
                message:
                  '현재 계정은 더 이상 사용할 수 없습니다.',
              },
              {
                status: 403,
              },
            )
          }

          console.error(
            'Effective actor preflight failed:',
            effectiveActorError,
          )

          return Response.json(
            {
              message:
                '계정 권한을 확인할 수 없습니다.',
            },
            {
              status: 500,
            },
          )
        }


        // ====================================================
        // MASTER ONLY
        // ====================================================

        const {
          data: actorProfile,
          error: actorError,
        } =
          await ctx.supabaseAdmin
            .from('profiles')
            .select(
              'role, is_active',
            )
            .eq(
              'id',
              actorId,
            )
            .single()

        if (
          actorError
          || !actorProfile
          || actorProfile.role !==
              'master'
          || actorProfile.is_active !==
              true
        ) {
          return Response.json(
            {
              message:
                '전체 관리자 권한이 필요합니다.',
            },
            {
              status: 403,
            },
          )
        }


        // ====================================================
        // REQUEST
        // ====================================================

        const body =
          await req.json()

        const name =
          normalizeName(
            typeof body.name ===
                'string'
              ? body.name
              : '',
          )

        const pin =
          typeof body.pin ===
              'string'
            ? body.pin
            : ''

        const branchId =
          typeof body.branchId ===
              'string'
            ? body.branchId.trim()
            : ''

        const workHours =
          Array.isArray(
            body.workHours,
          )
            ? body.workHours
            : []

        if (
          name.length === 0
          || name.length > 100
        ) {
          return Response.json(
            {
              message:
                '지점장 이름을 확인해주세요.',
            },
            {
              status: 400,
            },
          )
        }


        if (
          !PIN_PATTERN.test(pin)
        ) {
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


        if (
          !UUID_PATTERN.test(
            branchId,
          )
        ) {
          return Response.json(
            {
              message:
                '지점을 다시 선택해주세요.',
            },
            {
              status: 400,
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
          Deno.env.get(
            'PIN_PEPPER',
          )

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
        // CREATE HIDDEN AUTH USER
        // ====================================================

        const hiddenIdentity =
          crypto.randomUUID()

        const hiddenEmail =
          `${hiddenIdentity}@auth.forestring.invalid`

        const {
          data: authData,
          error: authError,
        } =
          await ctx.supabaseAdmin
            .auth.admin
            .createUser({
              email: hiddenEmail,
              email_confirm: true,
            })

        if (
          authError
          || !authData.user
        ) {
          console.error(
            'Manager Auth user creation failed:',
            authError,
          )

          return Response.json(
            {
              message:
                '지점장 계정 생성에 실패했습니다.',
            },
            {
              status: 500,
            },
          )
        }

        const managerId =
          authData.user.id


        // ====================================================
        // CREATE FORESTRING DATA
        // ====================================================

        const {
          error: dataError,
        } =
          await ctx.supabaseAdmin.rpc(
            'admin_create_manager_account_data',
            {
              p_actor_id:
                actorId,

              p_profile_id:
                managerId,

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
            'Manager DB creation failed:',
            dataError,
          )

          // Auth and PostgreSQL cannot share one transaction.
          // Delete the hidden Auth identity if DB creation fails.

          const {
            error: cleanupError,
          } =
            await ctx.supabaseAdmin
              .auth.admin
              .deleteUser(
                managerId,
              )

          if (cleanupError) {
            console.error(
              'CRITICAL: orphan manager Auth cleanup failed:',
              managerId,
              cleanupError,
            )
          }

          const message =
            dbMessage(
              dataError,
            )


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
              'FORESTRING_BRANCH_REQUIRED',
            )
            || message.includes(
              'FORESTRING_BRANCH_NOT_FOUND',
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


          if (
            message.includes(
              'FORESTRING_INVALID_WORK',
            )
            || message.includes(
              'FORESTRING_WORK_TIME_NOT_15_MINUTE_ALIGNED',
            )
          ) {
            return Response.json(
              {
                message:
                  '근무시간을 확인해주세요.',
              },
              {
                status: 400,
              },
            )
          }


          return Response.json(
            {
              message:
                '지점장 정보 저장에 실패했습니다.',
            },
            {
              status: 500,
            },
          )
        }


        return Response.json(
          {
            managerId,
            displayName: name,
            branchId,
          },
          {
            status: 201,
          },
        )
      } catch (error) {
        console.error(
          'master-create-manager failed:',
          error,
        )

        return Response.json(
          {
            message:
              '지점장 계정 생성 중 오류가 발생했습니다.',
          },
          {
            status: 500,
          },
        )
      }
    },
  ),
}
