# Fix for 401 Token Errors - Deployment Guide

## Problem Found

Your Flutter app was receiving **401 "Invalid token" errors** because:

1. **Malformed Firebase Configuration**: The `.env` file had `FIREBASE_CONFIG` with escaped newlines (`\\n`) wrapped in single quotes, which failed to parse on Render.com
2. **Poor Error Logging**: Backend error responses returned `{"error":{}}` instead of actual error messages, making debugging impossible

## Solution Applied

### 1. Fixed .env File ✅

- **OLD**: `FIREBASE_CONFIG` with inline escaped JSON (problematic)
- **NEW**: Uses `FIREBASE_SERVICE_ACCOUNT_JSON_PATH=./pay-65-firebase-adminsdk-fbsvc-1d36924356.json` (clean & reliable)
- **Backup**: Original .env saved as `.env.backup`

### 2. Improved Error Logging ✅

Added proper error serialization in:

- `userProfileController.ts` (getProfile, uploadProfilePic)
- `postController.ts` (createPost)

Now errors will show: `{"error": "actual error message"}` instead of `{"error": {}}`

## Deployment Steps

### Step 1: Update Backend on Render

1. Go to your Render.com dashboard
2. Navigate to your backend service
3. **Important**: DO NOT use `FIREBASE_CONFIG` environment variable
4. Remove any `FIREBASE_CONFIG` from your Render environment variables
5. Ensure `FIREBASE_SERVICE_ACCOUNT_JSON_PATH` is NOT set in Render (or set to blank)
6. **INSTEAD**: Ensure the actual JSON file `pay-65-firebase-adminsdk-fbsvc-1d36924356.json` is committed to your git repo and deployed with your code

### Step 2: Verify Firebase Credentials

Check your Render backend logs to confirm:

```
Firebase Admin initialized successfully { projectId: 'pay-65' }
```

### Step 3: Remove FIREBASE_CONFIG from Local .env

The fixed `.env` file in your project no longer has the problematic `FIREBASE_CONFIG`. Keep it this way.

### Step 4: Rebuild & Deploy

```bash
# Commit changes
git add .env .env.backup src/controllers/ src/config/
git commit -m "Fix Firebase config and improve error logging"
git push

# Render will auto-deploy
```

## Temporary Test (Optional)

If Render doesn't auto-deploy, manually trigger a rebuild in Render dashboard.

## Expected Results After Fix

- ✅ Creating posts will work
- ✅ Fetching posts on feed will work
- ✅ FCM token updates will work
- ✅ Profile fetching will work
- ✅ Better error messages in logs for debugging

## Cloudinary Notes

Photos/videos uploading to Cloudinary is separate - if you still see Cloudinary errors after this fix, we can debug that next. The 401 errors were blocking everything, so fixing those first will reveal any remaining Cloudinary issues.

## Important: Render Environment Variables

Do NOT add `FIREBASE_CONFIG` or `FIREBASE_SERVICE_ACCOUNT_JSON_PATH` to Render's environment variables if the JSON file is in your git repo.

The firebase.ts initialization will automatically:

1. Check `FIREBASE_CONFIG` env var first (don't use this on Render)
2. Then check `FIREBASE_SERVICE_ACCOUNT_JSON_PATH` env var (don't use this on Render)
3. Then try to read from `./pay-65-firebase-adminsdk-fbsvc-1d36924356.json` (the file in your repo)

## Debugging

After deployment, check Render logs for:

1. Firebase initialization message
2. Token verification attempts
3. Better error messages from profile/post endpoints

---

**Last Updated**: April 5, 2026
**Status**: Ready to Deploy
