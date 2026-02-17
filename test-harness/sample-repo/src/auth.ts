// Sample authentication module - needs error handling
export interface User {
  id: string;
  email: string;
  passwordHash: string;
}

export async function authenticateUser(email: string, password: string): Promise<User> {
  const response = await fetch('/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password })
  });
  
  if (!response.ok) {
    throw new Error('Authentication failed');
  }
  
  return response.json();
}

export async function refreshToken(token: string): Promise<string> {
  const response = await fetch('/api/auth/refresh', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}` }
  });
  
  return response.json();
}

export function validatePassword(password: string): boolean {
  return password.length >= 8;
}