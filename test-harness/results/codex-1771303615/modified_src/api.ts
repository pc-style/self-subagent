// Sample API module - needs error handling
import { authenticateUser } from './auth';
import { processPayment } from './payments';
import { getUserProfile } from './user';

export interface ApiRequest {
  endpoint: string;
  method: 'GET' | 'POST' | 'PUT' | 'DELETE';
  body?: unknown;
  headers?: Record<string, string>;
}

export interface ApiResponse<T> {
  data: T;
  status: number;
  headers: Record<string, string>;
}

export type ApiErrorCode =
  | 'API_REQUEST_FAILED'
  | 'API_INVALID_RESPONSE'
  | 'API_MIDDLEWARE_FAILED'
  | 'API_HANDLER_FAILED';

interface ApiLogEntry {
  timestamp: string;
  code: string;
  message: string;
  stack?: string;
}

export type Result<T, E extends Error> = { ok: true; data: T } | { ok: false; error: E };

export type ApiMiddleware = (request: ApiRequest) => ApiRequest | Promise<ApiRequest>;

export class ApiError extends Error {
  public readonly code: ApiErrorCode;

  public constructor(message: string, code: ApiErrorCode, options?: { cause?: unknown }) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    if (options?.cause !== undefined) {
      (this as Error & { cause?: unknown }).cause = options.cause;
    }
  }
}

function logApiError(error: ApiError): void {
  const entry: ApiLogEntry = {
    timestamp: new Date().toISOString(),
    code: error.code,
    message: error.message,
    stack: error.stack
  };
  console.error(entry);
}

function toApiError(error: unknown, fallbackCode: ApiErrorCode, fallbackMessage: string): ApiError {
  if (error instanceof ApiError) {
    return error;
  }
  if (error instanceof Error) {
    return new ApiError(error.message, fallbackCode, { cause: error });
  }
  return new ApiError(fallbackMessage, fallbackCode, { cause: error });
}

async function applyMiddlewares(
  request: ApiRequest,
  middlewares: readonly ApiMiddleware[]
): Promise<ApiRequest> {
  let currentRequest = request;

  for (const middleware of middlewares) {
    try {
      currentRequest = await middleware(currentRequest);
    } catch (error) {
      throw toApiError(error, 'API_MIDDLEWARE_FAILED', 'API middleware execution failed');
    }
  }

  return currentRequest;
}

export async function apiRequest<T>(
  request: ApiRequest,
  middlewares: readonly ApiMiddleware[] = []
): Promise<ApiResponse<T>> {
  try {
    const resolvedRequest = await applyMiddlewares(request, middlewares);
    const response = await fetch(resolvedRequest.endpoint, {
      method: resolvedRequest.method,
      headers: {
        'Content-Type': 'application/json',
        ...resolvedRequest.headers
      },
      body: resolvedRequest.body ? JSON.stringify(resolvedRequest.body) : undefined
    });

    if (!response.ok) {
      throw new ApiError(`API request failed with status ${response.status}`, 'API_REQUEST_FAILED');
    }

    const data = (await response.json()) as T;
    return {
      data,
      status: response.status,
      headers: {}
    };
  } catch (error) {
    const apiError = toApiError(error, 'API_INVALID_RESPONSE', 'API request handling failed');
    logApiError(apiError);
    throw apiError;
  }
}

export async function safeApiRequest<T>(
  request: ApiRequest,
  middlewares: readonly ApiMiddleware[] = []
): Promise<ApiResponse<Result<T, ApiError>>> {
  try {
    const response = await apiRequest<T>(request, middlewares);
    return {
      data: { ok: true, data: response.data },
      status: response.status,
      headers: response.headers
    };
  } catch (error) {
    const apiError = toApiError(error, 'API_REQUEST_FAILED', 'Safe API request failed');
    logApiError(apiError);
    return {
      data: { ok: false, error: apiError },
      status: 500,
      headers: {}
    };
  }
}

export async function handleAuth(email: string, password: string) {
  try {
    const user = await authenticateUser(email, password);
    return user;
  } catch (error) {
    const apiError = toApiError(error, 'API_HANDLER_FAILED', 'Authentication handler failed');
    logApiError(apiError);
    throw apiError;
  }
}

export async function handlePayment(userId: string, amount: number) {
  try {
    const payment = await processPayment(userId, amount, 'USD');
    return payment;
  } catch (error) {
    const apiError = toApiError(error, 'API_HANDLER_FAILED', 'Payment handler failed');
    logApiError(apiError);
    throw apiError;
  }
}

export async function handleUserProfile(userId: string) {
  try {
    const userProfile = await getUserProfile(userId);
    return userProfile;
  } catch (error) {
    const apiError = toApiError(error, 'API_HANDLER_FAILED', 'User profile handler failed');
    logApiError(apiError);
    throw apiError;
  }
}

export function withGlobalErrorHandling<TArgs extends unknown[], TResult>(
  handler: (...args: TArgs) => Promise<TResult>,
  code: ApiErrorCode = 'API_HANDLER_FAILED'
): (...args: TArgs) => Promise<Result<TResult, ApiError>> {
  return async (...args: TArgs): Promise<Result<TResult, ApiError>> => {
    try {
      const data = await handler(...args);
      return { ok: true, data };
    } catch (error) {
      const apiError = toApiError(error, code, 'Global handler captured an error');
      logApiError(apiError);
      return { ok: false, error: apiError };
    }
  };
}
