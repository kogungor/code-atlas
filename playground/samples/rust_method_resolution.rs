struct CheckoutService;

impl CheckoutService {
    fn apply_discount(&self, subtotal: f64) -> f64 {
        subtotal * 0.90
    }
}

struct AuditService;

impl AuditService {
    fn apply_discount(&self, subtotal: f64) -> f64 {
        subtotal * 0.99
    }
}

fn calculate_with_receivers(checkout_service: &CheckoutService, audit_service: &AuditService, subtotal: f64) -> f64 {
    let checkout_adjusted = checkout_service.apply_discount(subtotal);
    let audit_adjusted = audit_service.apply_discount(subtotal);
    checkout_adjusted.min(audit_adjusted)
}

pub fn run(subtotal: f64) -> f64 {
    let checkout_service = CheckoutService;
    let audit_service = AuditService;
    calculate_with_receivers(&checkout_service, &audit_service, subtotal)
}
