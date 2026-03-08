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

local function calculate_dynamic(service, subtotal)
  return service:apply_discount_rules(subtotal)
end

local M = {}

function M.run(subtotal)
  local checkout = CheckoutService.new()
  local audit = AuditService.new()
  local one = calculate_dynamic(checkout, subtotal)
  local two = calculate_dynamic(audit, subtotal)
  return math.min(one, two)
end

return M
