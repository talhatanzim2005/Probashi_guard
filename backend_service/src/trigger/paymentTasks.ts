import { logger, task } from "@trigger.dev/sdk";

export interface RemittanceNotificationPayload {
  transactionId: string;
  recipientName: string;
  recipientPhone: string;
  amountBDT: number;
  incentiveBDT: number;
  currency: string;
  timestamp: string;
}

export interface LedgerReconciliationPayload {
  transactionId: string;
  sourceCardId: string;
  destinationAccountId?: string;
  amount: number;
  currency: string;
  sourceAmount?: number;
  sourceCurrency?: string;
  exchangeRate?: number;
}

/**
 * Task for asynchronous remittance completion and notifications
 */
export const remittanceNotificationTask = task({
  id: "remittance-notification",
  maxDuration: 120,
  run: async (payload: RemittanceNotificationPayload, { ctx }) => {
    logger.log("Processing async remittance notification", { payload, ctx });

    // Emulate notification dispatch to Bangladesh SMS / Push gateway
    logger.info(`SMS sent to ${payload.recipientPhone}: Remittance of ৳${payload.amountBDT} (Bonus: ৳${payload.incentiveBDT}) received from Probashi Guard.`);

    return {
      status: "delivered",
      transactionId: payload.transactionId,
      deliveredAt: new Date().toISOString(),
    };
  },
});

/**
 * Task for background ledger reconciliation and audit tracking
 */
export const ledgerReconciliationTask = task({
  id: "ledger-reconciliation",
  maxDuration: 180,
  run: async (payload: LedgerReconciliationPayload, { ctx }) => {
    logger.log("Reconciling remittance ledger with host WPS bank", { payload, ctx });

    return {
      reconciled: true,
      transactionId: payload.transactionId,
      ledgerTimestamp: new Date().toISOString(),
    };
  },
});

/**
 * Safe invocation helper that triggers background operations without blocking or crashing Express
 */
export async function triggerPaymentTasksSafely(
  notification: RemittanceNotificationPayload,
  reconciliation: LedgerReconciliationPayload
): Promise<void> {
  try {
    if (process.env.TRIGGER_SECRET_KEY) {
      // Trigger async tasks non-blockingly
      remittanceNotificationTask.trigger(notification).catch((err) => {
        console.warn("[Trigger.dev] Non-fatal notification trigger warning:", err.message);
      });
      ledgerReconciliationTask.trigger(reconciliation).catch((err) => {
        console.warn("[Trigger.dev] Non-fatal ledger trigger warning:", err.message);
      });
    }
  } catch (err: any) {
    console.warn("[Trigger.dev] Background execution fallback:", err.message);
  }
}
