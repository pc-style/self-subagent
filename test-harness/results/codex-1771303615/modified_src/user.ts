// Sample user module - needs error handling
export interface UserProfile {
  id: string;
  name: string;
  email: string;
  preferences: Record<string, unknown>;
}

export type ValidationErrorCode =
  | 'VALIDATION_ERROR'
  | 'USER_FETCH_FAILED'
  | 'USER_UPDATE_FAILED'
  | 'USER_INVALID_RESPONSE';

interface ValidationLogEntry {
  timestamp: string;
  code: string;
  message: string;
  stack?: string;
}

export class ValidationError extends Error {
  public readonly code: ValidationErrorCode;

  public constructor(message: string, code: ValidationErrorCode, options?: { cause?: unknown }) {
    super(message);
    this.name = 'ValidationError';
    this.code = code;
    if (options?.cause !== undefined) {
      (this as Error & { cause?: unknown }).cause = options.cause;
    }
  }
}

function logValidationError(error: ValidationError): void {
  const entry: ValidationLogEntry = {
    timestamp: new Date().toISOString(),
    code: error.code,
    message: error.message,
    stack: error.stack
  };
  console.error(entry);
}

function toValidationError(
  error: unknown,
  fallbackCode: ValidationErrorCode,
  fallbackMessage: string
): ValidationError {
  if (error instanceof ValidationError) {
    return error;
  }
  if (error instanceof Error) {
    return new ValidationError(error.message, fallbackCode, { cause: error });
  }
  return new ValidationError(fallbackMessage, fallbackCode, { cause: error });
}

export async function getUserProfile(userId: string): Promise<UserProfile> {
  try {
    if (!userId.trim()) {
      throw new ValidationError('User ID is required', 'VALIDATION_ERROR');
    }

    const response = await fetch(`/api/users/${userId}`);
    if (!response.ok) {
      throw new ValidationError('Failed to fetch user profile', 'USER_FETCH_FAILED');
    }

    const data = (await response.json()) as UserProfile;
    return data;
  } catch (error) {
    const validationError = toValidationError(error, 'USER_INVALID_RESPONSE', 'User profile request failed');
    logValidationError(validationError);
    throw validationError;
  }
}

export async function updateUserProfile(userId: string, updates: Partial<UserProfile>): Promise<UserProfile> {
  try {
    if (!userId.trim()) {
      throw new ValidationError('User ID is required', 'VALIDATION_ERROR');
    }
    if (typeof updates.email === 'string' && !validateEmail(updates.email)) {
      throw new ValidationError('Invalid email format', 'VALIDATION_ERROR');
    }

    const response = await fetch(`/api/users/${userId}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(updates)
    });

    if (!response.ok) {
      throw new ValidationError('Failed to update user profile', 'USER_UPDATE_FAILED');
    }

    const data = (await response.json()) as UserProfile;
    return data;
  } catch (error) {
    const validationError = toValidationError(error, 'USER_INVALID_RESPONSE', 'User update request failed');
    logValidationError(validationError);
    throw validationError;
  }
}

export function validateEmail(email: string): boolean {
  try {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  } catch (error) {
    const validationError = toValidationError(error, 'VALIDATION_ERROR', 'Email validation failed');
    logValidationError(validationError);
    return false;
  }
}
