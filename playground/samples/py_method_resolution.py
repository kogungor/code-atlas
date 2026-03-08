class CheckoutService:
    def apply_discount(self, subtotal):
        return subtotal * 0.90


class AuditService:
    def apply_discount(self, subtotal):
        return subtotal * 0.99


def calculate_with_receivers(checkout_service: CheckoutService, audit_service: AuditService, subtotal: float):
    checkout_adjusted = checkout_service.apply_discount(subtotal)
    audit_adjusted = audit_service.apply_discount(subtotal)
    return min(checkout_adjusted, audit_adjusted)


def run(subtotal: float):
    checkout_service = CheckoutService()
    audit_service = AuditService()
    return calculate_with_receivers(checkout_service, audit_service, subtotal)
