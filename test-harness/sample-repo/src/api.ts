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

export async function apiRequest<T>(request: ApiRequest): Promise<ApiResponse<T>> {
  const response = await fetch(request.endpoint, {
    method: request.method,
    headers: {
      'Content-Type': 'application/json',
      ...request.headers
    },
    body: request.body ? JSON.stringify(request.body) : undefined
  });
  
  const data = await response.json();
  
  return {
    data,
    status: response.status,
    headers: {}
  };
}

export async function handleAuth(email: string, password: string) {
  const user = await authenticateUser(email, password);
  return user;
}

export async function handlePayment(userId: string, amount: number) {
  const payment = await processPayment(userId, amount, 'USD');
  return payment;
}