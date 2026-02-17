// Sample payments module - needs error handling
export interface Payment {
  id: string;
  amount: number;
  currency: string;
  status: 'pending' | 'completed' | 'failed';
}

export type PaymentErrorCode =
  | 'PAYMENT_DECLINED'
  | 'PAYMENT_NETWORK_ERROR'
  | 'PAYMENT_INVALID_RESPONSE'
  | 'PAYMENT_REFUND_FAILED';

interface PaymentLogEntry {
  timestamp: string;
  code: string;
  message: string;
  stack?: string;
}

export class PaymentError extends Error {
  public readonly code: PaymentErrorCode;

  public constructor(message: string, code: PaymentErrorCode, options?: { cause?: unknown }) {
    super(message);
    this.name = 'PaymentError';
    this.code = code;
    if (options?.cause !== undefined) {
      (this as Error & { cause?: unknown }).cause = options.cause;
    }
  }
}

function logPaymentError(error: PaymentError): void {
  const entry: PaymentLogEntry = {
    timestamp: new Date().toISOString(),
    code: error.code,
    message: error.message,
    stack: error.stack
  };
  console.error(entry);
}

function toPaymentError(error: unknown, fallbackCode: PaymentErrorCode, fallbackMessage: string): PaymentError {
  if (error instanceof PaymentError) {
    return error;
  }
  if (error instanceof Error) {
    return new PaymentError(error.message, fallbackCode, { cause: error });
  }
  return new PaymentError(fallbackMessage, fallbackCode, { cause: error });
}

export async function processPayment(userId: string, amount: number, currency: string): Promise<Payment> {
  try {
    const response = await fetch('/api/payments/process', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ userId, amount, currency })
    });

    if (!response.ok) {
      throw new PaymentError('Payment processing failed', 'PAYMENT_DECLINED');
    }

    const data = (await response.json()) as Payment;
    return data;
  } catch (error) {
    const paymentError = toPaymentError(error, 'PAYMENT_NETWORK_ERROR', 'Payment request failed');
    logPaymentError(paymentError);
    throw paymentError;
  }
}

export async function refundPayment(paymentId: string): Promise<Payment> {
  try {
    const response = await fetch(`/api/payments/${paymentId}/refund`, {
      method: 'POST'
    });

    if (!response.ok) {
      throw new PaymentError('Payment refund failed', 'PAYMENT_REFUND_FAILED');
    }

    const data = (await response.json()) as Payment;
    return data;
  } catch (error) {
    const paymentError = toPaymentError(error, 'PAYMENT_INVALID_RESPONSE', 'Refund request failed');
    logPaymentError(paymentError);
    throw paymentError;
  }
}

export function calculateFee(amount: number): number {
  return amount * 0.029 + 0.30;
}
