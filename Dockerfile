FROM node:18-bullseye

# Install system dependencies required for Playwright, Chrome extensions, Xvfb, FFmpeg and AWS CLI
RUN apt-get update \
    && apt-get install -y \
        wget \
        gnupg \
        libnss3 \
        libatk-bridge2.0-0 \
        libdrm2 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxrandr2 \
        libgbm1 \
        libxss1 \
        libasound2 \
        libxshmfence1 \
        xvfb \
        x11vnc \
        fluxbox \
        x11-utils \
        ffmpeg \
        curl \
        unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Optimize FFmpeg performance settings
ENV FFMPEG_THREAD_COUNT=0
ENV FFMPEG_PRESET=ultrafast

# Set CPU optimization flags
ENV NODE_OPTIONS="--max-old-space-size=2048"

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws/

# Create app directory
WORKDIR /app

# Copy dependency descriptors first for caching
COPY package.json package-lock.json ./
COPY chrome_extension/package.json chrome_extension/package-lock.json ./chrome_extension/

# Install dependencies for the server and the extension
RUN npm ci  \
    && npm ci --prefix chrome_extension

# Install Playwright browsers using the local version
RUN npx  playwright install --with-deps chromium

# Copy the rest of the application code
COPY . .

# Build the server and the Chrome extension
RUN npm run build  \
    && npm run build --prefix chrome_extension

# Verify extension build
RUN ls -la /app/chrome_extension/dist/ \
    && ls -la /app/chrome_extension/dist/js/

# Create startup script
RUN echo '#!/bin/bash\n\
echo "🖥️ Starting virtual display..."\n\
export DISPLAY=:99\n\
Xvfb :99 -screen 0 1280x720x24 -ac +extension GLX +render -noreset &\n\
XVFB_PID=$!\n\
echo "✅ Virtual display started (PID: $XVFB_PID)"\n\
\n\
# Wait for display to be ready\n\
sleep 2\n\
\n\
echo "🚀 Starting application..."\n\
cd /app/\n\
node build/src/main.js\n\
\n\
# Cleanup\n\
kill $XVFB_PID 2>/dev/null || true\n\
' > /start.sh && chmod +x /start.sh

WORKDIR /app/

ENV SERVERLESS=true
ENV NODE_ENV=production
ENV DISPLAY=:99

ENTRYPOINT ["/start.sh"]
