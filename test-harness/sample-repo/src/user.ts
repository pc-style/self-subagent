// Sample user module - needs error handling
export interface UserProfile {
  id: string;
  name: string;
  email: string;
  preferences: Record<string, unknown>;
}

export async function getUserProfile(userId: string): Promise<UserProfile> {
  const response = await fetch(`/api/users/${userId}`);
  
  return response.json();
}

export async function updateUserProfile(userId: string, updates: Partial<UserProfile>): Promise<UserProfile> {
  const response = await fetch(`/api/users/${userId}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(updates)
  });
  
  return response.json();
}

export function validateEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}