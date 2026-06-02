# ENCLINE Deployment Guide

This guide describes how to deploy the **ENCLINE Secure Messaging App** (both frontend web client and backend signaling server) to production.

---

## 1. Hosting the Frontend (Web Client)

Since the frontend compiled by Flutter is a static web app (`build/web` containing HTML, CSS, JS, and assets), it can be hosted on any static hosting provider. Below are the two easiest and most popular platforms, both of which support **automatic updates** when you push new code to GitHub.

---

### Option A: GitHub Pages (Easiest & fully automated via GitHub Actions)
With this method, every time you push code to your `main` branch, a GitHub Action automatically builds the Flutter Web app and publishes it to your GitHub Pages site.

#### Step 1: Create the GitHub Actions Workflow
We have pre-configured a workflow file at `.github/workflows/deploy.yml`. 
*When you push your repository to GitHub, this action is triggered automatically.*

#### Step 2: Configure GitHub Repository Settings
1. Go to your repository on GitHub.
2. Navigate to **Settings** > **Pages**.
3. Under **Build and deployment** > **Source**, choose **Deploy from a branch**.
4. Under **Branch**, select `gh-pages` and `/ (root)`, then click **Save**.
5. Ensure your workflow permissions allow writing to the repository:
   - Go to **Settings** > **Actions** > **General**.
   - Scroll down to **Workflow permissions** and select **Read and write permissions**, then click **Save**.

#### Step 3: Push to GitHub
As soon as you push your code:
```bash
git init
git add .
git commit -m "Deploy ENCLINE WhatsApp Web App"
git branch -M main
git remote add origin https://github.com/<your-username>/encline.git
git push -u origin main
```
GitHub Actions will automatically run the build and publish the site. It will be available at:
`https://<your-username>.github.io/encline/`

---

### Option B: Vercel (Fast & Premium Custom Domains)
Vercel is a premium serverless platform that is extremely fast. You can link your GitHub repository to Vercel for continuous automatic deployments.

#### Method 1: Local Build & Deploy (Direct Upload)
If you want to build the project on your machine and upload the static files directly to Vercel:
1. Build the web app locally:
   ```bash
   flutter build web --release
   ```
2. Navigate to the build output folder:
   ```bash
   cd frontend/build/web
   ```
3. Run the Vercel CLI to deploy:
   ```bash
   vercel --prod
   ```
*(You will need to sign in to Vercel and follow the prompts. Future updates are applied by rebuilding locally and running `vercel --prod` again).*

#### Method 2: Automatic Vercel Builds (Git Integrated)
To build and deploy automatically directly inside Vercel's servers on every git push, we can use a custom build script since Vercel's default environment doesn't include Flutter.

1. Create a `vercel.json` file in the root of the project with a custom build command that installs Flutter:
   ```json
   {
     "version": 2,
     "cleanUrls": true,
     "framework": null,
     "installCommand": "git clone https://github.com/flutter/flutter.git --depth 1 -b stable $color && export PATH=\"$PATH:`pwd`/flutter/bin\" && flutter doctor",
     "buildCommand": "export PATH=\"$PATH:`pwd`/flutter/bin\" && cd frontend && flutter build web --release",
     "outputDirectory": "frontend/build/web"
   }
   ```
2. Import your GitHub repository into Vercel:
   - Log in to [vercel.com](https://vercel.com).
   - Click **Add New** > **Project** and select your `encline` repository.
   - Vercel will detect the `vercel.json` config and execute the Flutter build automatically.
   - Every time you `git push`, Vercel will rebuild and update your site automatically!

---

## 2. Hosting the Backend (Signaling Server)

The signaling Node.js server (`backend/server.js`) must run continuously to negotiate connections. You can host it for free on **Render**, **Railway**, or **Hugging Face Spaces**.

### Deploying to Render (Free Web Service Tier)
1. Go to [render.com](https://render.com) and log in.
2. Click **New** > **Web Service**.
3. Connect your GitHub repository.
4. Set the following details:
   - **Name**: `encline-signaling`
   - **Root Directory**: `backend`
   - **Runtime**: `Node`
   - **Build Command**: `npm install`
   - **Start Command**: `node server.js`
5. Render will deploy the backend server and provide you with a public URL, for example:
   `https://encline-signaling.onrender.com`

---

## 3. Connecting Frontend to your Live Backend
1. Once your backend is deployed and running, copy its HTTPS URL (e.g. `https://encline-signaling.onrender.com`).
2. Open the ENCLINE web app in your browser.
3. Click the **Settings Gear Icon** in the sidebar.
4. Under **Signaling Server Config**, paste your live Render URL into the input field and click **Save Server Configuration**.
5. Your client is now connected to the public web server!
6. When creating or joining rooms, it will use this server. Direct WebRTC direct messages will connect directly between your devices, while signaling and fallbacks will use your secure Render URL.
