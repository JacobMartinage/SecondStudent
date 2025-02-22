import { useEffect } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { exchangeCodeForToken } from "../services/authService";

export default function OAuthCallback() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();

  useEffect(() => {
    const code = searchParams.get("code");
    if (code) {
      exchangeCodeForToken(code)
        .then(({ access_token }) => {
          localStorage.setItem("canvas_token", access_token); // Store token for API calls
          navigate("/dashboard");
        })
        .catch((err) => {
          console.error("OAuth Error:", err);
          navigate("/login");
        });
    }
  }, [searchParams, navigate]);

  return <p>Authenticating...</p>;
}
