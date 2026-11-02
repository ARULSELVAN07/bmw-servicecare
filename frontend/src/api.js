const apiUrl = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");

export async function request(path, token, options = {}) {
  if (!apiUrl) throw new Error("Frontend configuration is missing VITE_API_URL.");

  const response = await fetch(`${apiUrl}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(options.body ? { "Content-Type": "application/json" } : {}),
      ...options.headers,
    },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.message || `Request failed (${response.status})`);
  return body;
}

export function createTicket(token, details) {
  return request("/tickets", token, { method: "POST", body: JSON.stringify(details) });
}

export function getTicket(token, ticketId) {
  return request(`/tickets/${encodeURIComponent(ticketId)}`, token);
}

export function updateTicket(token, ticketId, updates) {
  return request(`/tickets/${encodeURIComponent(ticketId)}`, token, {
    method: "PUT",
    body: JSON.stringify(updates),
  });
}