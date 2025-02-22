import { redirectToCanvasOAuth } from '../services/authService';
import { Link } from 'react-router-dom';

export default function Login() {
  return (
    <div>
      <h1>Sign in with Canvas (Virginia Tech)</h1>
      <button onClick={redirectToCanvasOAuth}>Login with Canvas</button>
      <Link to="/Dashboard">dashboard</Link>
    </div>
  );
}
