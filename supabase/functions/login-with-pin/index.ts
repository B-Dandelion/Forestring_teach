import { withSupabase } from 'npm:@supabase/server@^1'
import { compare } from 'npm:bcryptjs@3.0.2'

const encoder = new TextEncoder()

const PIN_PATTERN = /^\d{4}$/

type RateLimitState = {
  failed_attempts: number
  window_started_at: string
  locked_until: string | null
}

type Credential = {
  profile_id: string
  pin_hash: string
  role:
    | 'master'
    | 'manager'
    | 'teacher'
    | 'student'
  is_active: boolean
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

  return Array.from(new Uint8Array(signature))
    .map(
      (byte) =>
        byte.toString(16).padStart(2, '0'),
    )
    .join('')
}

function getClientIp(req: Request): string {
  const forwarded =
    req.headers.get('x-forwarded-for')

  if (forwarded) {
    return forwarded.split(',')[0].trim()
  }

  return (
    req.headers.get('cf-connecting-ip')
    ?? 'unknown'
  )
}

function isLocked(
  state: RateLimitState | null,
): boolean {
  if (!state?.locked_until) {
    return false
  }

  return (
    new Date(state.locked_until).getTime()
    > Date.now()
  )
}

async function getRateLimit(
  supabaseAdmin: any,
  bucketKey: string,
): Promise<RateLimitState | null> {
  const { data, error } =
    await supabaseAdmin.rpc(
      'auth_get_login_rate_limit',
      {
        p_bucket_key: bucketKey,
      },
    )

  if (error) {
    throw error
  }

  if (
    !Array.isArray(data)
    || data.length === 0
  ) {
    return null
  }

  return data[0] as RateLimitState
}

async function recordFailure(
  supabaseAdmin: any,
  bucketKey: string,
  subjectKey: string | null,
  windowSeconds: number,
  maxAttempts: number,
  lockSeconds: number,
): Promise<void> {
  const { error } =
    await supabaseAdmin.rpc(
      'auth_record_login_failure_scoped',
      {
        p_bucket_key:
          bucketKey,

        p_subject_key:
          subjectKey,

        p_window_seconds:
          windowSeconds,

        p_max_attempts:
          maxAttempts,

        p_lock_seconds:
          lockSeconds,
      },
    )

  if (error) {
    throw error
  }
}

async function clearRateLimit(
  supabaseAdmin: any,
  bucketKey: string,
): Promise<void> {
  const { error } =
    await supabaseAdmin.rpc(
      'auth_clear_login_rate_limit',
      {
        p_bucket_key: bucketKey,
      },
    )

  if (error) {
    throw error
  }
}

export default {
  fetch: withSupabase(
    { auth: 'publishable' },

    async (req, ctx) => {
      if (req.method !== 'POST') {
        return Response.json(
          {
            message: 'Method not allowed.',
          },
          {
            status: 405,
          },
        )
      }

      try {
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

        if (
          name.length === 0 ||
          name.length > 100 ||
          !PIN_PATTERN.test(pin)
        ) {
          return Response.json(
            {
              message:
                '이름과 4자리 숫자 PIN을 확인해주세요.',
            },
            {
              status: 400,
            },
          )
        }

        const pinPepper =
          Deno.env.get('PIN_PEPPER')

        const ratePepper =
          Deno.env.get(
            'RATE_LIMIT_PEPPER',
          )

        if (!pinPepper || !ratePepper) {
          console.error(
            'Required authentication secrets are missing.',
          )

          return Response.json(
            {
              message:
                '로그인 서버 설정 오류입니다.',
            },
            {
              status: 500,
            },
          )
        }

        const ip = getClientIp(req)

        const nameBucket = await hmacHex(
          ratePepper,
          `name:${name}`,
        )

        const ipBucket = await hmacHex(
          ratePepper,
          `ip:${ip}`,
        )

        const pairBucket = await hmacHex(
          ratePepper,
          `pair:${name}:${ip}`,
        )

        const subjectKey = await hmacHex(
            ratePepper,
            `subject:${name}`,
        )

        const rateStates =
          await Promise.all([
            getRateLimit(
              ctx.supabaseAdmin,
              nameBucket,
            ),
            getRateLimit(
              ctx.supabaseAdmin,
              ipBucket,
            ),
            getRateLimit(
              ctx.supabaseAdmin,
              pairBucket,
            ),
          ])

        if (rateStates.some(isLocked)) {
          return Response.json(
            {
              message:
                '로그인 시도가 너무 많습니다. 잠시 후 다시 시도해주세요.',
            },
            {
              status: 429,
            },
          )
        }

        const pinFingerprint =
          await hmacHex(
            pinPepper,
            pin,
          )

        const {
          data: credentialData,
          error: credentialError,
        } = await (
          ctx.supabaseAdmin as any
        ).rpc(
          'auth_lookup_login_credential',
          {
            p_login_name_normalized:
              name,

            p_pin_fingerprint:
              pinFingerprint,
          },
        )


        if (credentialError) {
          throw credentialError
        }


        const credential: Credential | null =
          Array.isArray(credentialData)
          && credentialData.length > 0
            ? credentialData[0] as Credential
            : null


        // ====================================================
        // CREDENTIAL STATE
        //
        // Do not hide nullability behind a separate boolean.
        // Returning here lets TypeScript and runtime both know
        // that credential is valid below this point.
        // ====================================================

        if (
          credential === null
          || credential.is_active !== true
          || typeof credential.pin_hash !==
             'string'
        ) {
          await Promise.all([
            recordFailure(
              ctx.supabaseAdmin,
              nameBucket,
              subjectKey,
              15 * 60,
              10,
              15 * 60,
            ),

            recordFailure(
              ctx.supabaseAdmin,
              ipBucket,
              null,
              15 * 60,
              30,
              30 * 60,
            ),

            recordFailure(
              ctx.supabaseAdmin,
              pairBucket,
              subjectKey,
              10 * 60,
              5,
              15 * 60,
            ),
          ])


          return Response.json(
            {
              message:
                '이름 또는 PIN이 올바르지 않습니다.',
            },
            {
              status: 401,
            },
          )
        }


        // ====================================================
        // PIN VERIFICATION
        // ====================================================

        const authenticated =
          await compare(
            `${pin}:${pinPepper}`,
            credential.pin_hash,
          )


                if (!authenticated) {
                  await Promise.all([
                    recordFailure(
                      ctx.supabaseAdmin,
                      nameBucket,
                      subjectKey,
                      15 * 60,
                      10,
                      15 * 60,
                    ),

                    recordFailure(
                      ctx.supabaseAdmin,
                      ipBucket,
                      null,
                      15 * 60,
                      30,
                      30 * 60,
                    ),

                    recordFailure(
                      ctx.supabaseAdmin,
                      pairBucket,
                      subjectKey,
                      10 * 60,
                      5,
                      15 * 60,
                    ),
                  ])


                  return Response.json(
                    {
                      message:
                        '이름 또는 PIN이 올바르지 않습니다.',
                    },
                    {
                      status: 401,
                    },
                  )
                }


                // ====================================================
                // HIDDEN SUPABASE AUTH USER
                // ====================================================

                const {
                  data: userData,
                  error: userError,
                } =
                  await ctx.supabaseAdmin.auth.admin
                    .getUserById(
                      credential.profile_id,
                    )


                if (
                  userError
                  || !userData.user
                  || !userData.user.email
                ) {
                  throw (
                    userError
                    ?? new Error(
                      'Auth user email is missing.',
                    )
                  )
                }


                // ====================================================
                // LOGIN TOKEN
                // ====================================================

                const {
                  data: linkData,
                  error: linkError,
                } =
                  await ctx.supabaseAdmin.auth.admin
                    .generateLink({
                      type: 'magiclink',
                      email: userData.user.email,
                    })


                if (linkError) {
                  throw linkError
                }


                const tokenHash =
                  linkData.properties
                    ?.hashed_token


                if (!tokenHash) {
                  throw new Error(
                    'Supabase Auth did not return a token hash.',
                  )
                }


                // ====================================================
                // SUCCESS -> CLEAR NAME-RELATED RATE LIMITS
                //
                // IP bucket intentionally remains because it represents
                // aggregate activity from the client address.
                // ====================================================

                await Promise.all([
                  clearRateLimit(
                    ctx.supabaseAdmin,
                    nameBucket,
                  ),

                  clearRateLimit(
                    ctx.supabaseAdmin,
                    pairBucket,
                  ),
                ])


                return Response.json({
                  tokenHash,
                })

              } catch (error) {
                console.error(
                  'login-with-pin failed:',
                  error,
                )


                return Response.json(
                  {
                    message:
                      '로그인 처리 중 오류가 발생했습니다.',
                  },
                  {
                    status: 500,
                  },
                )
              }
            },
          ),
        }