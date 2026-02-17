// Sample payments module - needs error handling
export interface Payment {
  id: string;
  amount: number;
  currency: string;
  status: 'pending' | 'completed' | 'failed';
}

export async function processPayment(userId: string, amount: number, currency: string): Promise<Payment> {
  const response = await fetch('/api/payments/process', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ userId, amount, currency })
  });
  
  const data = await response.json();
  return data;
}

export async function refundPayment(paymentId: string): Promise<Payment> {
  const response = await fetch(`/api/payments/${paymentId}/refund`, {
    method: 'POST'
  });
  
  return response.json();
}

export function calculateFee(amount: number): number {
  return amount * 0.029 + 0.30;
}