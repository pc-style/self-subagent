// Sample utils module - needs error handling
export async function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

export function parseJSON<T>(json: string): T {
  return JSON.parse(json) as T;
}

export async function retry<T>(
  fn: () => Promise<T>,
  maxAttempts: number
): Promise<T> {
  let lastError: Error;
  
  for (let i = 0; i < maxAttempts; i++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error as Error;
      await delay(1000 * (i + 1));
    }
  }
  
  throw lastError!;
}

export function formatCurrency(amount: number, currency: string): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency
  }).format(amount);
}