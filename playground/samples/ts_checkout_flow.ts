import { formatReceiptLine, sendEmail } from "./ts_shared"

type CartItem = {
  name: string
  qty: number
  price: number
  stock: number
}

type Cart = {
  items: CartItem[]
}

type Customer = {
  id: string
  email: string
  tier?: "vip" | "standard"
  coupon?: string
}

type Payment = {
  customerId: string
  amount: number
  transactionId: string
  status: "paid"
}

function hasStock(item: CartItem): boolean {
  return item.stock > 0 && item.qty <= item.stock
}

function validateCart(cart: Cart): boolean {
  if (!cart || !cart.items || cart.items.length === 0) {
    return false
  }

  return cart.items.every((item) => item.qty > 0 && hasStock(item))
}

function sumItems(cart: Cart): number {
  return cart.items.reduce((acc, item) => acc + item.price * item.qty, 0)
}

function normalizeCoupon(code?: string): string | null {
  if (!code) {
    return null
  }
  return code.replace(/\s+/g, "").toUpperCase()
}

function customerHasCoupon(customer: Customer): boolean {
  return typeof customer.coupon === "string" && customer.coupon.length > 0
}

function isVipCustomer(customer: Customer): boolean {
  return customer.tier === "vip"
}

function applyDiscountRules(subtotal: number, customer: Customer): number {
  let discount = 0

  if (customerHasCoupon(customer)) {
    const coupon = normalizeCoupon(customer.coupon)
    if (coupon === "SAVE10") {
      discount += subtotal * 0.1
    }
  }

  if (isVipCustomer(customer)) {
    discount += subtotal * 0.05
  }

  return Math.min(discount, subtotal)
}

function calculateTax(amount: number): number {
  return amount * 0.2
}

function roundMoney(amount: number): number {
  return Math.round(amount * 100) / 100
}

function calculateTotal(cart: Cart, customer: Customer): number {
  const subtotal = sumItems(cart)
  const discount = applyDiscountRules(subtotal, customer)
  const taxedBase = subtotal - discount
  const tax = calculateTax(taxedBase)
  return roundMoney(taxedBase + tax)
}

function requestGateway(amount: number): { ok: true; txid: string } | { ok: false; error: string } {
  if (amount <= 0) {
    return { ok: false, error: "invalid amount" }
  }
  return { ok: true, txid: "tx_ts_12345" }
}

function chargePayment(customer: Customer, amount: number): Payment | null {
  const gateway = requestGateway(amount)
  if (!gateway.ok) {
    return null
  }

  return {
    customerId: customer.id,
    amount,
    transactionId: gateway.txid,
    status: "paid",
  }
}

function renderReceipt(cart: Cart, total: number): string {
  const lines = cart.items.map((item) => formatReceiptLine(item.name, item.qty, item.price))
  lines.push(`TOTAL: ${total.toFixed(2)}`)
  return lines.join("\n")
}

export function checkout(cart: Cart, customer: Customer):
  | { total: number; payment: Payment; receipt: { to: string; body: string } }
  | { error: string } {
  if (!validateCart(cart)) {
    return { error: "invalid cart" }
  }

  const total = calculateTotal(cart, customer)
  const payment = chargePayment(customer, total)
  if (!payment) {
    return { error: "payment failed" }
  }

  const receipt = renderReceipt(cart, total)
  const delivery = sendEmail(customer.email, receipt)

  return {
    total,
    payment,
    receipt: delivery,
  }
}
