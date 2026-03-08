package samples

type CheckoutService struct{}

func (s *CheckoutService) ApplyDiscount(subtotal float64) float64 {
	return subtotal * 0.90
}

type AuditService struct{}

func (s *AuditService) ApplyDiscount(subtotal float64) float64 {
	return subtotal * 0.99
}

func CalculateWithReceivers(checkoutService *CheckoutService, auditService *AuditService, subtotal float64) float64 {
	checkoutAdjusted := checkoutService.ApplyDiscount(subtotal)
	auditAdjusted := auditService.ApplyDiscount(subtotal)
	if checkoutAdjusted < auditAdjusted {
		return checkoutAdjusted
	}
	return auditAdjusted
}

func Run(subtotal float64) float64 {
	checkoutService := &CheckoutService{}
	auditService := &AuditService{}
	return CalculateWithReceivers(checkoutService, auditService, subtotal)
}
