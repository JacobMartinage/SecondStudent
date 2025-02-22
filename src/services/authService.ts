const CANVAS_BASE_URL = "https://canvas.vt.edu";
const CLIENT_ID = import.meta.env.VITE_CANVAS_CLIENT_ID;
const REDIRECT_URI = import.meta.env.VITE_CANVAS_REDIRECT_URI;

// Redirect user to Canvas OAuth page
export const redirectToCanvasOAuth = () => {
  const authUrl = `${CANVAS_BASE_URL}/login/oauth2/auth?client_id=${CLIENT_ID}&response_type=code&redirect_uri=${encodeURIComponent(REDIRECT_URI)}`;
  window.location.href = authUrl;
};

// Exchange authorization code for access token
export const exchangeCodeForToken = async (code: string) => {
  const response = await fetch(`${CANVAS_BASE_URL}/login/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      grant_type: "authorization_code",
      client_id: CLIENT_ID,
      client_secret: import.meta.env.VITE_CANVAS_CLIENT_SECRET,
      redirect_uri: REDIRECT_URI,
      code,
    }),
  });

  if (!response.ok) throw new Error("Token exchange failed");
  return response.json(); // { access_token, refresh_token, expires_in }
};
