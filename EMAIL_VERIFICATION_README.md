# Email Verification Setup Guide

## Overview
This implementation provides **true email existence verification** by checking if an email address can actually receive emails using SMTP verification.

## How It Works
1. **Client-side**: Flutter app sends email to backend API
2. **Backend**: Node.js server attempts SMTP verification
3. **Verification**: Server tries to send a test email to check deliverability
4. **Response**: Returns detailed verification results

## Setup Instructions

### 1. Backend Setup

```bash
cd backend
npm install
```

### 2. Configure Environment Variables

Edit `backend/.env`:
```env
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
PORT=3000
```

**Important**: Use an App Password for Gmail, not your regular password.

### 3. Start Backend Server

```bash
cd backend
npm start
```

### 4. Update Flutter API URL

In `lib/email_verification_service.dart`, update the `_apiUrl`:
```dart
static const String _apiUrl = 'http://localhost:3000/verify-email';
// For production: 'https://your-backend-domain.com/verify-email'
```

### 5. Install Flutter Dependencies

```bash
flutter pub get
```

## Verification Results

The system returns detailed information:

```json
{
  "isValid": true,
  "isDeliverable": true,
  "provider": "Gmail",
  "isDisposable": false,
  "isRoleAccount": false
}
```

## Error Handling

- **Invalid Format**: Basic regex validation
- **Non-existent Domain**: DNS/MX record check
- **Undeliverable**: SMTP server rejects email
- **Disposable Email**: Common temp services blocked
- **Role Account**: Generic addresses flagged

## Deployment Options

### Option 1: Heroku
```bash
heroku create your-email-verifier
git push heroku main
```

### Option 2: Railway/Vercel
Deploy the Node.js app to your preferred platform.

### Option 3: Firebase Cloud Functions
```javascript
// functions/index.js
const functions = require('firebase-functions');
const nodemailer = require('nodemailer');

exports.verifyEmail = functions.https.onCall(async (data, context) => {
  // SMTP verification logic here
});
```

## Security Considerations

- **Rate Limiting**: Implement to prevent abuse
- **API Keys**: Use authentication for production
- **Logging**: Monitor verification attempts
- **Caching**: Cache results to reduce SMTP calls

## Testing

Test with various email types:
- ✅ `user@gmail.com` (valid, deliverable)
- ❌ `user@nonexistent123.com` (invalid domain)
- ❌ `user@10minutemail.com` (disposable)
- ❌ `admin@company.com` (role account)

## Limitations

- **SMTP Blocking**: Some providers block SMTP verification
- **Privacy**: Verification attempts may be logged by email providers
- **Rate Limits**: Email providers may limit verification attempts
- **Cost**: High-volume verification may require paid SMTP services

## Alternative Services

For production, consider using:
- **SendGrid** Email Validation API
- **Mailgun** Email Verification
- **NeverBounce** API
- **Hunter.io** Email Verification

These services handle the complexities of email verification at scale.