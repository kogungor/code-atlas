local CheckoutService = {}
CheckoutService.__index = CheckoutService

function CheckoutService.new()
  return setmetatable({}, CheckoutService)
end

function CheckoutService:apply_discount_rules(subtotal)
  return subtotal * 0.90
end

local AuditService = {}
AuditService.__index = AuditService

function AuditService.new()
  return setmetatable({}, AuditService)
end

function AuditService:apply_discount_rules(subtotal)
  return subtotal * 0.99
end

local function calculate_with_receivers(subtotal)
  local checkout_service = CheckoutService.new()
  local audit_service = AuditService.new()

  local checkout_adjusted = checkout_service:apply_discount_rules(subtotal)
  local audit_adjusted = audit_service:apply_discount_rules(subtotal)
  return math.min(checkout_adjusted, audit_adjusted)
end

local M = {}

function M.run(subtotal)
  return calculate_with_receivers(subtotal)
end

return M
