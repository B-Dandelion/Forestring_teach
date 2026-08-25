import { withSupabase } from 'npm:@supabase/server@^1'

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

function normalizeName(
  value: string,
): string {
  return value
    .normalize('NFC')
    .trim()
    .replace(/\s+/g, ' ')
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
        // 1. AUTH TOKEN
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
        // 2. REQUEST
        // ====================================================

        const body =
          await req.json() as {
            profileId?: unknown
            name?: unknown
          }


        const profileId =
          typeof body.profileId ===
              'string'
            ? body.profileId.trim()
            : ''


        const name =
          normalizeName(
            typeof body.name ===
                'string'
              ? body.name
              : '',
          )


        if (
          !UUID_PATTERN.test(
            profileId,
          )
        ) {
          return Response.json(
            {
              message:
                '수정할 계정을 다시 선택해주세요.',
            },
            {
              status: 400,
            },
          )
        }


        if (
          name.length === 0
          || name.length > 100
        ) {
          return Response.json(
            {
              message:
                '이름을 확인해주세요.',
            },
            {
              status: 400,
            },
          )
        }


        // ====================================================
        // 3. DATABASE
        //
        // Authorization is intentionally checked AGAIN inside
        // the transaction RPC.
        // ====================================================

        const {
          data,
          error,
        } =
          await (
            ctx.supabaseAdmin as any
          ).rpc(
            'admin_update_account_name_data',
            {
              p_actor_id:
                actorId,

              p_profile_id:
                profileId,

              p_display_name:
                name,

              p_login_name_normalized:
                name,
            },
          )


        if (error) {
          console.error(
            'Account name update failed:',
            error,
          )

          const message =
            dbMessage(error)


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
              'FORESTRING_ACCOUNT_NAME_UPDATE_FORBIDDEN',
            )
            || message.includes(
              'FORESTRING_MANAGER_BRANCH_FORBIDDEN',
            )
          ) {
            return Response.json(
              {
                message:
                  '이 계정의 이름을 변경할 권한이 없습니다.',
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
              'FORESTRING_LOGIN_CREDENTIAL_REQUIRED',
            )
          ) {
            console.error(
              'Profile exists without login credential:',
              profileId,
            )

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
            || message.includes(
              'FORESTRING_ACCOUNT_NAME_MISMATCH',
            )
          ) {
            return Response.json(
              {
                message:
                  '이름을 확인해주세요.',
              },
              {
                status: 400,
              },
            )
          }


          return Response.json(
            {
              message:
                '이름 변경 중 오류가 발생했습니다.',
            },
            {
              status: 500,
            },
          )
        }


        return Response.json({
          account: data,
        })

      } catch (error) {
        console.error(
          'staff-update-account-name failed:',
          error,
        )

        return Response.json(
          {
            message:
              '이름 변경 처리 중 오류가 발생했습니다.',
          },
          {
            status: 500,
          },
        )
      }
    },
  ),
}