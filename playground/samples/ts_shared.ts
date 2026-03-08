export function formatReceiptLine(name: string, qty: number, unitPrice: number): string {
  const lineTotal = qty * unitPrice
  return `${name} x${qty} = ${lineTotal.toFixed(2)}`
}

export function sendEmail(to: string, body: string): { to: string; body: string } {
  return { to, body }
}
