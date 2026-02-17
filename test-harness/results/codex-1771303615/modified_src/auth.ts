// Sample authentication module - needs error handling
export interface User {
  id: string;
  email: string;
  passwordHash: string;
}

export type AuthErrorCode =
  | 'AUTH_FAILED'
  | 'AUTH_NETWORK_ERROR'
  | 'AUTH_INVALID_RESPONSE'
  | 'AUTH_TOKEN_REFRESH_FAILED';

interface AuthLogEntry {
  timestamp: string;
  code: string;
  message: string;
  stack?: string;
}

export class AuthError extends Error {
  public readonly code: AuthErrorCode;

  public constructor(message: string, code: AuthErrorCode, options?: { cause?: unknown }) {
    super(message);
    this.name = 'AuthError';
    this.code = code;
    if (options?.cause !== undefined) {
      (this as Error & { cause?: unknown }).cause = options.cause;
    }
  }
}

function logAuthError(error: AuthError): void {
  const entry: AuthLogEntry = {
    timestamp: new Date().toISOString(),
    code: error.code,
    message: error.message,
    stack: error.stack
  };
  console.error(entry);
}

function toAuthError(error: unknown, fallbackCode: AuthErrorCode, fallbackMessage: string): AuthError {
  if (error instanceof AuthError) {
    return error;
  }
  if (error instanceof Error) {
    return new AuthError(error.message, fallbackCode, { cause: error });
  }
  return new AuthError(fallbackMessage, fallbackCode, { cause: error });
}

export async function authenticateUser(email: string, password: string): Promise<User> {
  try {
    const response = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });

    if (!response.ok) {
      throw new AuthError('Authentication failed', 'AUTH_FAILED');
    }

    const data = (await response.json()) as User;
    return data;
  } catch (error) {
    const authError = toAuthError(error, 'AUTH_NETWORK_ERROR', 'Authentication request failed');
    logAuthError(authError);
    throw authError;
  }
}

export async function refreshToken(token: string): Promise<string> {
  try {
    const response = await fetch('/api/auth/refresh', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` }
    });

    if (!response.ok) {
      throw new AuthError('Token refresh failed', 'AUTH_TOKEN_REFRESH_FAILED');
    }

    const data = (await response.json()) as string;
    return data;
  } catch (error) {
    const authError = toAuthError(error, 'AUTH_INVALID_RESPONSE', 'Token refresh request failed');
    logAuthError(authError);
    throw authError;
  }
}

export function validatePassword(password: string): boolean {
  return password.length >= 8;
}
