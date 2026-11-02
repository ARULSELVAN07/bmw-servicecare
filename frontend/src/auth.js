const config = {
  domain: import.meta.env.VITE_COGNITO_DOMAIN,
  clientId: import.meta.env.VITE_COGNITO_CLIENT_ID,
  redirectUri: import.meta.env.VITE_REDIRECT_URI,
  logoutUri: import.meta.env.VITE_LOGOUT_URI,
};

const verifierKey = "servicecare.pkce.verifier";
const stateKey = "servicecare.oauth.state";
const tokenKey = "servicecare.id_token";

function readTokenPayload(token) {
  const encoded = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  const padded = encoded.padEnd(Math.ceil(encoded.length / 4) * 4, "=");
  return JSON.parse(atob(padded));
}

function randomString(length = 64) {
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function createChallenge(verifier) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  const bytes = new Uint8Array(digest);
  const binary = String.fromCharCode(...bytes);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function beginSignIn() {
  const missingConfig = Object.entries(config).filter(([, value]) => !value).map(([key]) => key);
  if (missingConfig.length) {
    throw new Error(`Frontend configuration is incomplete: ${missingConfig.join(", ")}`);
  }

  const verifier = randomString();
  const state = randomString(24);
  sessionStorage.setItem(verifierKey, verifier);
  sessionStorage.setItem(stateKey, state);

  const challenge = await createChallenge(verifier);
  const url = new URL(`${config.domain}/oauth2/authorize`);
  url.search = new URLSearchParams({
    response_type: "code",
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    scope: "openid email profile",
    code_challenge_method: "S256",
    code_challenge: challenge,
    state,
  }).toString();
  window.location.assign(url);
}

export async function finishSignIn() {
  const callback = new URL(window.location.href);
  const oauthError = callback.searchParams.get("error_description") || callback.searchParams.get("error");
  if (oauthError) throw new Error(oauthError.replaceAll("+", " "));

  const code = callback.searchParams.get("code");
  if (!code) {
    const savedToken = sessionStorage.getItem(tokenKey);
    if (savedToken && readTokenPayload(savedToken).exp > Date.now() / 1000) return savedToken;
    sessionStorage.removeItem(tokenKey);
    return null;
  }

  const expectedState = sessionStorage.getItem(stateKey);
  if (!expectedState || callback.searchParams.get("state") !== expectedState) {
    throw new Error("Sign-in could not be verified. Please try again.");
  }

  const verifier = sessionStorage.getItem(verifierKey);
  if (!verifier) throw new Error("Your sign-in session expired. Please try again.");

  const response = await fetch(`${config.domain}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      client_id: config.clientId,
      code,
      redirect_uri: config.redirectUri,
      code_verifier: verifier,
    }),
  });
  const tokens = await response.json();
  if (!response.ok || !tokens.id_token) {
    throw new Error(tokens.error_description || "Unable to finish sign-in.");
  }

  sessionStorage.setItem(tokenKey, tokens.id_token);
  sessionStorage.removeItem(verifierKey);
  sessionStorage.removeItem(stateKey);
  window.history.replaceState({}, document.title, window.location.pathname);
  return tokens.id_token;
}

export function signOut() {
  sessionStorage.removeItem(tokenKey);
  sessionStorage.removeItem(verifierKey);
  sessionStorage.removeItem(stateKey);
  const url = new URL(`${config.domain}/logout`);
  url.search = new URLSearchParams({ client_id: config.clientId, logout_uri: config.logoutUri }).toString();
  window.location.assign(url);
}

export function getUserEmail(token) {
  try {
    return readTokenPayload(token).email || "ServiceCare user";
  } catch {
    return "ServiceCare user";
  }
}

export function getUserGroups(token) {
  try {
    const groups = readTokenPayload(token)["cognito:groups"] || [];
    return Array.isArray(groups) ? groups : [groups];
  } catch {
    return [];
  }
}