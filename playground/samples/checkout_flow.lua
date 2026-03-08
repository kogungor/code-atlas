local M = {}
local shared = require("playground.samples.lua_sample")

local function has_stock(item)
  return item.stock > 0 and item.qty <= item.stock
end

local function validate_cart_items(cart)
  for _, item in ipairs(cart.items) do
    if item.qty <= 0 then
      return false
    end
    if not has_stock(item) then
      return false
    end
  end
  return true
end

local function validate_cart(cart)
  if cart == nil or cart.items == nil or #cart.items == 0 then
    return false
  end
  return validate_cart_items(cart)
end

local function sum_items(cart)
  local total = 0
  for _, item in ipairs(cart.items) do
    total = total + (item.price * item.qty)
  end
  return total
end

local function normalize_coupon(code)
  if not code then
    return nil
  end
  return string.upper(code:gsub("%s+", ""))
end

local function customer_has_coupon(customer)
  return customer and customer.coupon ~= nil and customer.coupon ~= ""
end

local function is_vip_customer(customer)
  return customer and customer.tier == "vip"
end

local function apply_discount_rules(subtotal, customer)
  local discount = 0

  if customer_has_coupon(customer) then
    local coupon = normalize_coupon(customer.coupon)
    if coupon == "SAVE10" then
      discount = discount + (subtotal * 0.10)
    end
  end

  if is_vip_customer(customer) then
    discount = discount + (subtotal * 0.05)
  end

  if discount > subtotal then
    discount = subtotal
  end

  return discount
end

local function calculate_tax(amount)
  return amount * 0.20
end

local function round_money(amount)
  return math.floor((amount * 100) + 0.5) / 100
end

local function calculate_total(cart, customer)
  local subtotal = sum_items(cart)
  local discount = apply_discount_rules(subtotal, customer)
  local taxed_base = subtotal - discount
  local tax = calculate_tax(taxed_base)
  return round_money(taxed_base + tax)
end

local function build_payment_payload(customer, amount)
  return {
    customer_id = customer.id,
    amount = amount,
    currency = "USD",
  }
end

local function request_gateway(payload)
  if payload.amount <= 0 then
    return false, "invalid amount"
  end
  return true, "tx_12345"
end

local function persist_transaction(customer, amount, txid)
  return {
    customer_id = customer.id,
    amount = amount,
    transaction_id = txid,
    status = "paid",
  }
end

local function charge_payment(customer, amount)
  local payload = build_payment_payload(customer, amount)
  local ok, txid = request_gateway(payload)
  if not ok then
    return nil, txid
  end
  return persist_transaction(customer, amount, txid), nil
end

local function render_receipt_line(item)
  return string.format("%s x%d = %.2f", format_name(item.name), item.qty, item.price * item.qty)
end

local function render_receipt(cart, total)
  local lines = {}
  for _, item in ipairs(cart.items) do
    lines[#lines + 1] = render_receipt_line(item)
  end
  lines[#lines + 1] = string.format("TOTAL: %.2f", total)
  return table.concat(lines, "\n")
end

local function send_receipt(customer, receipt)
  shared.run()
  return {
    to = customer.email,
    body = receipt,
  }
end

function M.checkout(cart, customer)
  if not validate_cart(cart) then
    return nil, "invalid cart"
  end

  local total = calculate_total(cart, customer)
  local payment, payment_err = charge_payment(customer, total)
  if not payment then
    return nil, payment_err
  end

  local receipt = render_receipt(cart, total)
  local delivery = send_receipt(customer, receipt)

  return {
    total = total,
    payment = payment,
    receipt = delivery,
  }, nil
end

return M
