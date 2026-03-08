class CheckoutService {
  applyDiscountRules(subtotal: number): number {
    return subtotal * 0.9
  }
}

class AuditService {
  applyDiscountRules(subtotal: number): number {
    return subtotal * 0.99
  }
}

function calculateWithReceivers(
  checkoutService: CheckoutService,
  auditService: AuditService,
  subtotal: number
): number {
  const checkoutAdjusted = checkoutService.applyDiscountRules(subtotal)
  const auditAdjusted = auditService.applyDiscountRules(subtotal)
  return Math.min(checkoutAdjusted, auditAdjusted)
}

export function runScenario(subtotal: number): number {
  const checkoutService = new CheckoutService()
  const auditService = new AuditService()
  return calculateWithReceivers(checkoutService, auditService, subtotal)
}
