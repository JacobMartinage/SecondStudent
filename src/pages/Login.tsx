import { redirectToCanvasOAuth } from "../services/authService";

export default function Login() {
  return (
    <div>
      <h1>Sign in with Canvas (Virginia Tech)</h1>
      <button onClick={redirectToCanvasOAuth}>Login with Canvas</button>
    </div>
  );
}
