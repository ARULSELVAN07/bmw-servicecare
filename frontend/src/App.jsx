import { useEffect, useState } from "react";
import {
  ArrowUpRight,
  BadgeCheck,
  CarFront,
  Check,
  ChevronRight,
  CircleHelp,
  ClipboardList,
  Clock3,
  KeyRound,
  LoaderCircle,
  LogOut,
  Search,
  Send,
  ShieldCheck,
  Wrench,
} from "lucide-react";
import { createTicket, getTicket, updateTicket } from "./api.js";
import { beginSignIn, finishSignIn, getUserEmail, getUserGroups, signOut } from "./auth.js";

const tabs = [
  { id: "new", label: "New request", icon: Wrench },
  { id: "track", label: "Track a request", icon: Search },
  { id: "advisor", label: "Advisor update", icon: ClipboardList },
];

function App() {
  const [token, setToken] = useState("");
  const [authLoading, setAuthLoading] = useState(true);
  const [authError, setAuthError] = useState("");
  const [activeTab, setActiveTab] = useState("new");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState(null);
  const [ticket, setTicket] = useState(null);
  const [ticketId, setTicketId] = useState("");

  useEffect(() => {
    finishSignIn()
      .then((idToken) => setToken(idToken || ""))
      .catch((error) => setAuthError(error.message))
      .finally(() => setAuthLoading(false));
  }, []);

  async function handleSubmit(event) {
    event.preventDefault();
    const form = event.currentTarget;
    setBusy(true);
    setNotice(null);
    setTicket(null);
    const data = new FormData(event.currentTarget);
    try {
      const created = await createTicket(token, {
        customer_name: data.get("customer_name"),
        email: data.get("email"),
        vehicle: `${data.get("model")} ${data.get("registration")}`.trim(),
        concern: data.get("concern"),
      });
      setTicket(created);
      setNotice({ kind: "success", text: "Your request is now with the ServiceCare team." });
      form.reset();
    } catch (error) {
      setNotice({ kind: "error", text: error.message });
    } finally {
      setBusy(false);
    }
  }

  async function handleLookup(event) {
    event.preventDefault();
    setBusy(true);
    setNotice(null);
    setTicket(null);
    try {
      const result = await getTicket(token, ticketId.trim());
      setTicket(result);
      setNotice({ kind: "success", text: "Request details loaded." });
    } catch (error) {
      setNotice({ kind: "error", text: error.message });
    } finally {
      setBusy(false);
    }
  }

  async function handleAdvisorUpdate(event) {
    event.preventDefault();
    setBusy(true);
    setNotice(null);
    const data = new FormData(event.currentTarget);
    try {
      const updated = await updateTicket(token, ticketId.trim(), {
        status: data.get("status"),
        advisor_notes: data.get("advisor_notes"),
      });
      setTicket(updated);
      setNotice({ kind: "success", text: "Request updated." });
    } catch (error) {
      setNotice({ kind: "error", text: error.message });
    } finally {
      setBusy(false);
    }
  }

  if (authLoading) return <LoadingScreen />;
  if (!token) {
    return <SignInScreen error={authError} onSignIn={beginSignIn} />;
  }

  const email = getUserEmail(token);
  const isAdvisor = getUserGroups(token).includes("ServiceAdvisors");
  const visibleTabs = tabs.filter((tab) => tab.id !== "advisor" || isAdvisor);

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <a className="brand" href="#home" aria-label="BMW ServiceCare home">
          <span className="brand-mark"><CarFront size={21} strokeWidth={2.2} /></span>
          <span className="brand-name">Service<span>Care</span></span>
        </a>
        <div className="sidebar-label">YOUR SERVICE</div>
        <nav className="side-nav" aria-label="Service tools">
          {visibleTabs.map(({ id, label, icon: Icon }) => (
            <button
              className={`nav-item ${activeTab === id ? "active" : ""}`}
              key={id}
              onClick={() => { setActiveTab(id); setNotice(null); setTicket(null); }}
              type="button"
            >
              <Icon size={18} strokeWidth={1.8} />
              <span>{label}</span>
              {activeTab === id && <ChevronRight className="nav-chevron" size={15} />}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="help-box">
            <span className="help-icon"><CircleHelp size={17} /></span>
            <p>Need a hand?</p>
            <span>Our service team is ready to help.</span>
            <a href="mailto:service@example.com">Contact support <ArrowUpRight size={13} /></a>
          </div>
          <button className="signout-button" onClick={signOut} type="button">
            <LogOut size={17} /> Sign out
          </button>
        </div>
      </aside>

      <main className="main-area">
        <header className="topbar">
          <div className="breadcrumb">ServiceCare <span>/</span> {tabs.find((item) => item.id === activeTab)?.label}</div>
          <div className="account-chip">
            <span className="account-avatar">{email.charAt(0).toUpperCase()}</span>
            <span className="account-email">{email}</span>
            <BadgeCheck size={16} className="verified-icon" />
          </div>
        </header>

        <section className="page-content">
          <div className="welcome-row">
            <div>
              <p className="eyebrow"><span className="eyebrow-dot" /> BMW SERVICECARE</p>
              <h1>{activeTab === "new" ? "How can we help?" : activeTab === "track" ? "Your service requests" : "Advisor workspace"}</h1>
              <p className="page-subtitle">
                {activeTab === "new" ? "Tell us what your BMW needs. We’ll take it from here." : activeTab === "track" ? "Check the latest details and status of a request." : "Keep a customer request moving with a clear update."}
              </p>
            </div>
            <div className="response-note"><Clock3 size={16} /><span>Replies usually arrive within <strong>one business day</strong></span></div>
          </div>

          <div className="workspace-grid">
            <section className="form-panel">
              <div className="panel-heading">
                <div>
                  <span className="step-label">{activeTab === "new" ? "01 / REQUEST DETAILS" : activeTab === "track" ? "REQUEST LOOKUP" : "SERVICE UPDATE"}</span>
                  <h2>{activeTab === "new" ? "Start a service request" : activeTab === "track" ? "Find your request" : "Update a request"}</h2>
                </div>
                <span className="panel-heading-icon">{activeTab === "new" ? <Wrench size={20} /> : activeTab === "track" ? <Search size={20} /> : <ClipboardList size={20} />}</span>
              </div>

              {activeTab === "new" && <form className="service-form" onSubmit={handleSubmit}>
                <div className="field-row">
                  <label>Full name<input name="customer_name" autoComplete="name" placeholder="e.g. Alex Morgan" required /></label>
                  <label>Email address<input name="email" type="email" autoComplete="email" placeholder="you@example.com" required /></label>
                </div>
                <div className="field-row">
                  <label>BMW model<input name="model" placeholder="e.g. 3 Series" required /></label>
                  <label>Registration<input name="registration" placeholder="e.g. AB12 CDE" /></label>
                </div>
                <label>How can we help?<textarea name="concern" rows="4" placeholder="Describe the issue, service needed, or question..." required /></label>
                <div className="form-footer">
                  <span><ShieldCheck size={15} /> Your details are kept secure</span>
                  <button className="primary-button" disabled={busy} type="submit">
                    {busy ? <LoaderCircle className="spin" size={17} /> : <Send size={16} />} Send request
                  </button>
                </div>
              </form>}

              {activeTab === "track" && <form className="service-form short-form" onSubmit={handleLookup}>
                <label>Request reference<input value={ticketId} onChange={(event) => setTicketId(event.target.value)} placeholder="Paste your ticket reference" required /></label>
                <div className="form-footer"><span><KeyRound size={15} /> Your reference is in the confirmation</span><button className="primary-button" disabled={busy} type="submit">{busy ? <LoaderCircle className="spin" size={17} /> : <Search size={16} />} Find request</button></div>
              </form>}

              {activeTab === "advisor" && <form className="service-form short-form" onSubmit={handleAdvisorUpdate}>
                <label>Request reference<input value={ticketId} onChange={(event) => setTicketId(event.target.value)} placeholder="Enter a ticket reference" required /></label>
                <div className="field-row">
                  <label>Status<select name="status" defaultValue="IN_PROGRESS"><option value="OPEN">Open</option><option value="IN_PROGRESS">In progress</option><option value="WAITING_FOR_CUSTOMER">Waiting for customer</option><option value="RESOLVED">Resolved</option></select></label>
                  <label>Advisor note<input name="advisor_notes" placeholder="Add a short update" required /></label>
                </div>
                <div className="form-footer"><span><ShieldCheck size={15} /> Updates are recorded on the request</span><button className="primary-button" disabled={busy} type="submit">{busy ? <LoaderCircle className="spin" size={17} /> : <Check size={17} />} Save update</button></div>
              </form>}

              {notice && <div className={`notice ${notice.kind}`} role="status">{notice.kind === "success" ? <Check size={17} /> : <CircleHelp size={17} />} {notice.text}</div>}
              {ticket && <TicketResult ticket={ticket} />}
            </section>

            <aside className="side-column">
              <section className="vehicle-panel">
                <img src="https://images.unsplash.com/photo-1492144534655-ae79c964c9d7?auto=format&fit=crop&w=1000&q=85" alt="Modern car parked outdoors" />
                <div className="vehicle-overlay">
                  <span>CARE THAT MOVES WITH YOU</span>
                  <p>Every detail,<br />thoughtfully handled.</p>
                </div>
              </section>
              <section className="promise-panel">
                <div className="promise-heading"><span className="promise-icon"><ShieldCheck size={18} /></span><h3>Service, made simple</h3></div>
                <ul>
                  <li><span><Check size={12} /></span> A real person reviews your request</li>
                  <li><span><Check size={12} /></span> Updates stay in one place</li>
                  <li><span><Check size={12} /></span> Your vehicle details stay private</li>
                </ul>
              </section>
              <div className="secure-footnote"><span className="secure-dot" /> Secure customer portal <span className="footnote-divider">·</span> Cognito protected</div>
            </aside>
          </div>
          <footer className="page-footer"><span>BMW ServiceCare</span><span>Designed for confidence on every journey</span></footer>
        </section>
      </main>
    </div>
  );
}

function TicketResult({ ticket }) {
  return (
    <section className="ticket-result" aria-live="polite">
      <div className="result-topline"><span>REQUEST REFERENCE</span><span className="status-pill">{ticket.status || "OPEN"}</span></div>
      <strong className="ticket-id">{ticket.ticket_id}</strong>
      <div className="result-details">
        <span><b>Vehicle</b>{ticket.vehicle || "Not provided"}</span>
        <span><b>Submitted</b>{ticket.created_at ? new Date(ticket.created_at).toLocaleString() : "Just now"}</span>
      </div>
      {ticket.advisor_notes && <p className="advisor-note"><b>Advisor update</b>{ticket.advisor_notes}</p>}
    </section>
  );
}

function SignInScreen({ error, onSignIn }) {
  const [localError, setLocalError] = useState("");

  async function handleSignIn() {
    setLocalError("");
    try {
      await onSignIn();
    } catch (signInError) {
      setLocalError(signInError.message);
    }
  }

  return (
    <main className="signin-screen">
      <section className="signin-visual">
        <img src="https://images.unsplash.com/photo-1492144534655-ae79c964c9d7?auto=format&fit=crop&w=1800&q=90" alt="A modern vehicle ready for the road" />
        <div className="visual-wash" />
        <a className="brand visual-brand" href="#home"><span className="brand-mark"><CarFront size={21} /></span><span className="brand-name">Service<span>Care</span></span></a>
        <div className="visual-caption"><span>BMW SERVICECARE</span><h1>Confidence in<br />every mile.</h1><p>Thoughtful care for your vehicle, and the people who drive it.</p></div>
        <div className="visual-index">01 <span /> 03</div>
      </section>
      <section className="signin-side">
        <div className="signin-content">
          <span className="signin-kicker"><span /> YOUR SERVICE, IN ONE PLACE</span>
          <h2>Welcome back.</h2>
          <p>Sign in securely to raise a service request, follow its progress, or connect with your advisor.</p>
          {(error || localError) && <div className="notice error" role="alert"><CircleHelp size={17} />{localError || error}</div>}
          <button className="signin-button" onClick={handleSignIn} type="button"><KeyRound size={18} /> Continue with secure sign-in <ArrowUpRight size={17} /></button>
          <div className="signin-assurance"><ShieldCheck size={17} /><span>Protected by BMW ServiceCare identity</span></div>
        </div>
        <div className="signin-bottom"><span>BMW ServiceCare</span><span>Support for every journey</span></div>
      </section>
    </main>
  );
}

function LoadingScreen() {
  return <main className="loading-screen"><span className="loading-mark"><CarFront size={23} /></span><LoaderCircle className="spin" size={22} /><span>Securing your session</span></main>;
}

export default App;