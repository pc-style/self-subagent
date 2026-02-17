// Sample utils module - needs error handling
export type UtilityErrorCode =
  | 'INVALID_DELAY_MS'
  | 'JSON_PARSE_ERROR'
  | 'RETRY_FAILED'
  | 'RETRY_INVALID_ATTEMPTS'
  | 'FORMAT_CURRENCY_ERROR';

interface UtilityLogEntry {
  timestamp: string;
  code: string;
  message: string;
  stack?: string;
}

class UtilityError extends Error {
  public readonly code: UtilityErrorCode;

  public constructor(message: string, code: UtilityErrorCode, options?: { cause?: unknown }) {
    super(message);
    this.name = 'UtilityError';
    this.code = code;
    if (options?.cause !== undefined) {
      (this as Error & { cause?: unknown }).cause = options.cause;
    }
  }
}

function logUtilityError(error: UtilityError): void {
  const entry: UtilityLogEntry = {
    timestamp: new Date().toISOString(),
    code: error.code,
    message: error.message,
    stack: error.stack
  };
  console.error(entry);
}

function toUtilityError(error: unknown, fallbackCode: UtilityErrorCode, fallbackMessage: string): UtilityError {
  if (error instanceof UtilityError) {
    return error;
  }
  if (error instanceof Error) {
    return new UtilityError(error.message, fallbackCode, { cause: error });
  }
  return new UtilityError(fallbackMessage, fallbackCode, { cause: error });
}

export async function delay(ms: number): Promise<void> {
  try {
    if (!Number.isFinite(ms) || ms < 0) {
      throw new UtilityError('Delay duration must be a non-negative finite number', 'INVALID_DELAY_MS');
    }
    await new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  } catch (error) {
    const utilityError = toUtilityError(error, 'INVALID_DELAY_MS', 'Delay operation failed');
    logUtilityError(utilityError);
    throw utilityError;
  }
}

export function parseJSON<T>(json: string): T {
  try {
    return JSON.parse(json) as T;
  } catch (error) {
    const utilityError = toUtilityError(error, 'JSON_PARSE_ERROR', 'Failed to parse JSON');
    logUtilityError(utilityError);
    throw utilityError;
  }
}

export async function retry<T>(
  fn: () => Promise<T>,
  maxAttempts: number
): Promise<T> {
  if (!Number.isInteger(maxAttempts) || maxAttempts < 1) {
    const utilityError = new UtilityError('maxAttempts must be a positive integer', 'RETRY_INVALID_ATTEMPTS');
    logUtilityError(utilityError);
    throw utilityError;
  }

  let lastError: UtilityError | null = null;

  for (let i = 0; i < maxAttempts; i += 1) {
    try {
      return await fn();
    } catch (error) {
      lastError = toUtilityError(error, 'RETRY_FAILED', `Attempt ${i + 1} failed`);
      logUtilityError(lastError);
      if (i < maxAttempts - 1) {
        await delay(1000 * (i + 1));
      }
    }
  }

  throw lastError ?? new UtilityError('Retry failed without error details', 'RETRY_FAILED');
}

export function formatCurrency(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency
    }).format(amount);
  } catch (error) {
    const utilityError = toUtilityError(error, 'FORMAT_CURRENCY_ERROR', 'Currency formatting failed');
    logUtilityError(utilityError);
    throw utilityError;
  }
}
