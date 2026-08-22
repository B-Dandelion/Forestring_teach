import { withSupabase } from 'npm:@supabase/server@^1'
import { hash } from 'npm:bcryptjs@3.0.2'

const encoder =
  new TextEncoder()

const PIN_PATTERN =
  /^\d{4}$/

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i


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


function errorResponse(
  message: string,
): Response {
  if (
    message.includes(
      'FORESTRING_PIN_RESET_FORBIDDEN',
    )
    || message.includes(
      'FORESTRING_MANAGER_BRANCH_FORBIDDEN',
    )
  ) {
    return Response.json(
      {
        message:
          '이 계정의 PIN을 재설정할 권한이 없습니다.',
      },
      {
        status: 403,
      },
    )
  }


  if (
    message.includes(
      'FORESTRING_PROFILE_NOT_FOUND',
    )
  ) {
    return Response.json(
      {
        message:
          '계정을 찾을 수 없습니다.',
      },
      {
        status: 404,
      },
    )
  }


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
      'FORESTRING_LOGIN_NAME_CHANGED_RETRY',
    )
  ) {
    return Response.json(
      {
        message:
          '계정 정보가 변경되었습니다. 다시 시도해주세요.',
      },
      {
        status: 409,
      },
    )
  }


  if (
    message.includes(
      'FORESTRING_LOGIN_CREDENTIAL_REQUIRED',
    )
  ) {
    return Response.json(
      {
        message:
          '계정 로그인 정보가 올바르지 않습니다.',
      },
      {
        status: 500,
      },
    )
  }


  if (
    message.includes(
      'FORESTRING_INVALID_',
    )
  ) {
    return Response.json(
      {
        message:
          '입력 정보를 다시 확인해주세요.',
      },
      {
        status: 400,
      },
    )
  }


  return Response.json(
    {
      message:
        'PIN 재설정 중 오류가 발생했습니다.',
    },
    {
      status: 500,
    },
  )
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
        // 1. AUTH
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
            .getUser(
              accessToken,
            )


        if (
          authUserError
          || !authUserData.user
        ) {
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
        // 2. REQUEST
        // ====================================================

        const body =
          await req.json() as {
            profileId?: unknown
            pin?: unknown
          }


        const profileId =
          typeof body.profileId ===
              'string'
            ? body.profileId.trim()
            : ''


        const pin =
          typeof body.pin ===
              'string'
            ? body.pin
            : ''


        if (
          !UUID_PATTERN.test(
            profileId,
          )
        ) {
          return Response.json(
            {
              message:
                'PIN을 변경할 계정을 다시 선택해주세요.',
            },
            {
              status: 400,
            },
          )
        }


        if (
          !PIN_PATTERN.test(
            pin,
          )
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


        // ====================================================
        // 3. SECRETS
        // ====================================================

        const pinPepper =
          Deno.env.get(
            'PIN_PEPPER',
          )

        const ratePepper =
          Deno.env.get(
            'RATE_LIMIT_PEPPER',
          )


        if (
          !pinPepper
          || !ratePepper
        ) {
          console.error(
            'Required PIN reset secrets are missing.',
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


        // ====================================================
        // 4. RESET CONTEXT
        //
        // DB validates authorization before returning the
        // target's current normalized login name.
        // ====================================================

        const {
          data: contextData,
          error: contextError,
        } =
          await (
            ctx.supabaseAdmin as any
          ).rpc(
            'admin_get_account_pin_reset_context',
            {
              p_actor_id:
                actorId,

              p_profile_id:
                profileId,
            },
          )


        if (contextError) {
          console.error(
            'PIN reset context failed:',
            contextError,
          )

          return errorResponse(
            dbMessage(
              contextError,
            ),
          )
        }


        if (
          typeof contextData !==
            'string'
          || contextData.length === 0
        ) {
          console.error(
            'PIN reset context returned invalid login name.',
          )

          return Response.json(
            {
              message:
                '계정 로그인 정보를 확인할 수 없습니다.',
            },
            {
              status: 500,
            },
          )
        }


        const loginNameNormalized =
          contextData


        // ====================================================
        // 5. PREPARE PIN MATERIAL
        //
        // Raw PIN NEVER enters PostgreSQL.
        // ====================================================

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


        const rateLimitSubjectKey =
          await hmacHex(
            ratePepper,
            `subject:${loginNameNormalized}`,
          )


        // ====================================================
        // 6. ATOMIC RESET + UNLOCK
        //
        // DB transaction performs:
        //   credential lock
        //   login-name race guard
        //   authorization re-check
        //   PIN mutation
        //   audit
        //   name/pair rate-limit clear
        // ====================================================

        const {
          data: resetData,
          error: resetError,
        } =
          await (
            ctx.supabaseAdmin as any
          ).rpc(
            'admin_reset_account_pin_and_unlock_data',
            {
              p_actor_id:
                actorId,

              p_profile_id:
                profileId,

              p_pin_hash:
                pinHash,

              p_pin_fingerprint:
                pinFingerprint,

              p_expected_login_name_normalized:
                loginNameNormalized,

              p_rate_limit_subject_key:
                rateLimitSubjectKey,
            },
          )


        if (resetError) {
          console.error(
            'Atomic PIN reset failed:',
            resetError,
          )

          return errorResponse(
            dbMessage(
              resetError,
            ),
          )
        }


        // ====================================================
        // 7. SUCCESS
        //
        // NEVER return hash / fingerprint / raw PIN.
        // ====================================================

        return Response.json(
          {
            account:
              resetData,
          },
        )

      } catch (error) {
        console.error(
          'staff-reset-account-pin failed:',
          error,
        )


        return Response.json(
          {
            message:
              'PIN 재설정 처리 중 오류가 발생했습니다.',
          },
          {
            status: 500,
          },
        )
      }
    },
  ),
}