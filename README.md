# 🎭 ppt-orchestrator

> **A zero-dependency, highly robust web-based PowerPoint orchestration tool built for real-world stage managers and event staff.**

`ppt-orchestrator` enables seamless, zero-downtime transitions between multiple speakers' slide decks using just a smartphone or tablet. It requires **no third-party software installation** (like Node.js or Python) on the host PC, making it the perfect solution for strict corporate environments where installing external software is prohibited.

---

## 📖 Background (The Story Behind the Tool)

I created `ppt-orchestrator` out of pure frustration with how presentation events are typically handled at companies and schools. Time and again, I witnessed events delayed or derailed by clumsy slide transitions, accidental misclicks, and technical hiccups. 

Worse yet, simply because I was "the guy who knows a bit about computers," I was constantly appointed as the designated slide-switcher. It was a tedious and stressful role where a single misclick could launch the wrong presentation and cause frustrating delays to the entire event schedule.

I wanted to solve this problem once and for all and automate myself out of that stressful job. My absolute non-negotiable requirement for this project was that **the solution had to be completely self-contained using only standard Windows features**. It had to be strictly "zero-dependency" with absolutely no additional installations required, ensuring it could be instantly deployed on any heavily restricted corporate PC.

---

## 💡 Why This Exists (Solving Real-World Challenges)

Running a multi-speaker event often comes with severe operational headaches. This tool was engineered specifically to solve them:

* 🚫 **The "No Install" Constraint:** Corporate PCs often block third-party software. **Solution:** Built entirely on native Windows tools (PowerShell & Batch). If you have Windows and PowerPoint, it just works.
* 📶 **Unstable Venue Wi-Fi:** Mobile devices go to sleep, or venue Wi-Fi drops momentarily. **Solution:** Engineered with a robust polling architecture. The server safely ignores broken pipes and client disconnects, and the web UI features an auto-reconnecting offline overlay. The presentation will *never* crash due to a network drop.
* 🔒 **Unauthorized Access Risk:** Using an open venue Wi-Fi means anyone could potentially discover and access the web remote. **Solution:** Built-in Secure PIN Authentication. A dynamic 6-digit PIN is generated on the host PC, ensuring only authorized staff can control the slides.
* 📺 **Ugly Desktop Transitions:** Dragging windows or showing the file explorer to the audience looks unprofessional. **Solution:** Frictionless switching. Launch the next slide deck with a single tap, eliminating the clumsy desktop navigation between speakers.
* ⚠️ **Human Error Under Pressure:** Clicking the wrong file or repeating a speaker during a fast-paced event. **Solution:** Disabled console close buttons, Y/N exit confirmations, and smart queue management that automatically moves finished presentations to a `finish/` directory.

---

## ✨ Key Features (v1.0)

- **📱 Mobile Web Remote:** Control presentations directly from your phone's browser.
- **🔐 Secure PIN Authentication:** Protects your session with a randomly generated 6-digit One-Time PIN.
- **🔄 Seamless Transitions:** Instant, full-screen switching between `.ppt` / `.pptx` files.
- **🗂️ Auto-Queue & Pagination:** Automatically sorts files into "Pending" and "Completed" lists. Supports pagination for large-scale events with many speakers.
- **🛡️ Auto-Configuration & Cleanup:** The included Batch file automatically handles Administrator elevation, Windows Firewall rules, and URLACL bindings—and cleanly removes them upon exit.

---

## 📂 Directory Structure

Place your PowerPoint files in the **root folder** (same level as `Start-Presenter.bat`). Run `build/build.ps1` once to generate `dist/presentation-controller.ps1` before the first launch.

```text
ppt-orchestrator/
│
├── Start-Presenter.bat              # 🚀 The Launcher (Handles Elevation & Network config)
├── README.md                        # 📖 Documentation
│
├── 01_Opening_Remarks.pptx          # ⬅️ Drop your presentation files here
├── 02_Keynote_Speech.pptx           # ⬅️ (Files are sorted alphabetically)
│
├── src/                             # 📦 Modular source files
│   ├── config.ps1                   #    Parameters & script-scope variables
│   ├── templates.ps1                #    HTML/CSS/JS templates
│   ├── utils.ps1                    #    Utility functions
│   ├── auth.ps1                     #    PIN authentication
│   ├── server.ps1                   #    HTTP request routing
│   ├── ui-console.ps1               #    Console UI & keyboard input
│   ├── com-handler.ps1              #    PowerPoint COM monitoring
│   └── main.ps1                     #    Entry point (dot-sources all modules)
│
├── build/
│   └── build.ps1                    # 🔨 Combines src/ into a single deployable script
│
├── dist/                            # 🚫 Git-ignored (auto-generated by build.ps1)
│   └── presentation-controller.ps1 # ⚙️ The built, deployable script
│
└── finish/                          # 📁 Auto-generated at runtime
    └── 00_Test_Slide.pptx           # ⬅️ Finished presentations are moved here

```

---

## 🚀 How to Use

### Prerequisites

1. A Windows PC with **Microsoft PowerPoint** installed.
2. The PC and your mobile device must be on the **same network** (Wi-Fi or LAN).

### Step-by-Step Guide

1. **Prepare the Files**
Place all your `.ppt` or `.pptx` files in the root folder containing the scripts. (Tip: Prefix file names with numbers like `01_...`, `02_...` for guaranteed order).
2. **Launch the Server**
Double-click `Start-Presenter.bat`.
* *Note: It will prompt for Administrator privileges (UAC). This is required to temporarily configure the Windows Firewall and `http.sys` to allow web traffic.*


3. **Connect & Authenticate**
The PC console will display a **Web URL** (e.g., `http://192.168.x.x:8090/`) and a **6-digit PIN CODE**. Open the URL on your smartphone and enter the PIN to unlock the remote.
4. **Control the Show**
* **Lobby Screen:** Select a specific file from the queue or simply press **"Start"**.
* **Now Presenting:** The slide will open full-screen on the PC. You can monitor the status on your phone.
* **Post-Presentation:** When a slide deck ends, the file is moved to the `finish/` folder. Your phone will prompt you to start the "Next" slide, Retry, or return to the Lobby.


5. **Clean Shutdown**
Click **"Exit System"** on your mobile device, or press `Q` in the PC console (requires `Y` confirmation). The script will safely close PowerPoint and clean up all temporary Firewall and network rules.

---

## 🛠️ Advanced Operations (PC Console)

If the Wi-Fi completely fails and you lose access to the web remote, the host PC operator can still fully control the flow using the keyboard in the console window:

* `[Enter]` / `[S]`: Start / Next Slide
* `[1]` - `[9]`: Jump to a specific file in the current queue page
* `[N]` / `[P]`: Next Page / Previous Page (when handling many files)
* `[U]`: Update Network Info (re-fetches IP addresses)
* `[R]`: Retry the current slide
* `[L]`: Back to Lobby
* `[Q]` or `[ESC]`: Initiate safe system shutdown (Prompts for `Y/N` confirmation)

---

## ❓ Troubleshooting

**Q: The web page isn't loading on my phone.**

> Ensure your phone and the host PC are connected to the exact same Wi-Fi network. If the network changes, press `[U]` on the PC console to refresh the displayed IP addresses.

**Q: I get a "Port in use" error.**

> Port `8090` might be used by another application. You can change the port by editing `set "WEB_PORT=8090"` in the `.bat` file and `[int]$WebPort = 8090` in the `.ps1` file.

**Q: Does it support clickers / presentation remotes?**

> Yes! The speaker can use a standard USB clicker to advance their slides while they are speaking. `ppt-orchestrator` simply manages the "switching" between files behind the scenes.
