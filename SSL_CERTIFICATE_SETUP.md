# 🔐 SSL Certificate Issue for dstreambolt.click

## ❌ **Problem**

When accessing https://dstreambolt.click/, you get:
- **Error:** `curl: (35) Server aborted the SSL handshake`
- **Browser:** SSL certificate error or connection refused

## 🔍 **Root Cause**

The AWS Application Load Balancer (ALB) currently has a certificate for `*.elb.amazonaws.com`, NOT for `dstreambolt.click`.

```
Current Certificate: *.elb.amazonaws.com  ❌ (Wrong domain)
Your Domain:         dstreambolt.click    ✅ (DNS points correctly)
```

## ✅ **Solution**

You need to:
1. Request an AWS ACM certificate for `dstreambolt.click` and `*.dstreambolt.click`
2. Validate the certificate using DNS CNAME records
3. Attach the validated certificate to the ALB HTTPS listener

---

## 📋 **Step-by-Step Fix**

### ✅ **Step 1: Certificate Requested**

A certificate has been requested:
- **ARN:** `arn:aws:acm:ap-south-1:771239567939:certificate/5933eefb-e9f4-4293-9ed3-c020ea1d78ab`
- **Domains:** `dstreambolt.click` and `*.dstreambolt.click`
- **Status:** PENDING_VALIDATION

### 🎯 **Step 2: Add DNS CNAME Record to HostAsia**

You MUST add this CNAME record to validate the certificate:

```
Record Type: CNAME
Name:  _e5a93565e3c0c146efa9468fbe176157.dstreambolt.click
Value: _884793f939ee503829710ba40dcae37d.jkddzztszm.acm-validations.aws.
TTL:   300 (or default)
```

**Important Notes:**
- ⚠️  Remove the trailing dot (`.`) if your DNS provider doesn't support it
- ⚠️  Some providers want just the subdomain part: `_e5a93565e3c0c146efa9468fbe176157`
- ✅ Both domains (apex and wildcard) use the SAME validation record

#### **How to Add in HostAsia:**

1. **Log in to HostAsia Control Panel**
   - URL: https://my.hostasia.com/ (or your control panel URL)

2. **Navigate to DNS Management**
   - Find your domain: `dstreambolt.click`
   - Click "Manage DNS" or "DNS Records"

3. **Add New CNAME Record**
   ```
   Type:  CNAME
   Host:  _e5a93565e3c0c146efa9468fbe176157
   Value: _884793f939ee503829710ba40dcae37d.jkddzztszm.acm-validations.aws.
   TTL:   300
   ```

4. **Save the Record**

5. **Wait 5-10 minutes** for DNS propagation

---

### 🔍 **Step 3: Verify DNS Propagation**

After adding the CNAME, check if it's propagating:

```bash
# Check if validation CNAME exists
dig +short _e5a93565e3c0c146efa9468fbe176157.dstreambolt.click CNAME

# Should return:
# _884793f939ee503829710ba40dcae37d.jkddzztszm.acm-validations.aws.
```

Or use online DNS checker:
- https://dnschecker.org/
- Enter: `_e5a93565e3c0c146efa9468fbe176157.dstreambolt.click`
- Type: CNAME

---

### ⏳ **Step 4: Wait for AWS Certificate Validation**

Once DNS record is added and propagated, AWS will automatically validate:

**Option A: Wait and Check (Automatic)**
```bash
# Check certificate status
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:ap-south-1:771239567939:certificate/5933eefb-e9f4-4293-9ed3-c020ea1d78ab \
  --region ap-south-1 \
  --query 'Certificate.Status' \
  --output text

# Should eventually return: ISSUED
```

**Option B: Wait with AWS CLI**
```bash
aws acm wait certificate-validated \
  --certificate-arn arn:aws:acm:ap-south-1:771239567939:certificate/5933eefb-e9f4-4293-9ed3-c020ea1d78ab \
  --region ap-south-1

# This will wait up to 40 minutes
```

**Typical Timeline:**
- DNS propagation: 5-10 minutes
- AWS validation check: 1-5 minutes
- Total: 10-15 minutes (can take up to 30 minutes)

---

### 🔧 **Step 5: Update ALB with New Certificate**

Once certificate status is **ISSUED**, run:

```bash
# Automatic update
./scripts/setup_domain_ssl.sh
```

Or manually:

```bash
# Get HTTPS listener ARN
LISTENER_ARN=$(aws elbv2 describe-listeners \
  --load-balancer-arn arn:aws:elasticloadbalancing:ap-south-1:771239567939:loadbalancer/app/dstreambolt-alb/755e9c234508892f \
  --region ap-south-1 \
  --query 'Listeners[?Port==`443`].ListenerArn' \
  --output text)

# Update listener with new certificate
aws elbv2 modify-listener \
  --listener-arn $LISTENER_ARN \
  --certificates CertificateArn=arn:aws:acm:ap-south-1:771239567939:certificate/5933eefb-e9f4-4293-9ed3-c020ea1d78ab \
  --region ap-south-1
```

---

## ✅ **Verification**

After completing all steps:

```bash
# Test SSL connection
curl -I https://dstreambolt.click

# Should return HTTP/2 200 (or 301/302 redirect)
# No SSL errors
```

**Access your services:**
- https://dstreambolt.click/
- https://jenkins.dstreambolt.click/
- https://grafana.dstreambolt.click/
- https://spark.dstreambolt.click/
- https://kafkamgr.dstreambolt.click/

---

## 📊 **Current Status**

| Item | Status |
|------|--------|
| Domain DNS (A records) | ✅ Configured (points to ALB) |
| ACM Certificate Request | ✅ Created |
| DNS Validation Record | ⏳ **NEEDS TO BE ADDED** |
| Certificate Status | ⏳ PENDING_VALIDATION |
| ALB HTTPS Listener | ⏳ Waiting for certificate |

---

## 🔄 **Quick Commands**

### Check Certificate Status
```bash
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:ap-south-1:771239567939:certificate/5933eefb-e9f4-4293-9ed3-c020ea1d78ab \
  --region ap-south-1 \
  --query 'Certificate.{Status:Status,Validations:DomainValidationOptions[0].ValidationStatus}' \
  --output table
```

### Get Validation Record Again
```bash
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:ap-south-1:771239567939:certificate/5933eefb-e9f4-4293-9ed3-c020ea1d78ab \
  --region ap-south-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
  --output table
```

### Re-run Setup Script
```bash
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt
./scripts/setup_domain_ssl.sh
```

---

## 🛠️ **Troubleshooting**

### Issue: Certificate stays PENDING_VALIDATION

**Check DNS Record:**
```bash
dig _e5a93565e3c0c146efa9468fbe176157.dstreambolt.click CNAME
```

**Solutions:**
1. Verify CNAME record is added correctly in HostAsia
2. Wait longer (up to 30 minutes)
3. Check DNS propagation globally: https://dnschecker.org/
4. Ensure no typos in the CNAME name or value

### Issue: DNS propagation is slow

**Check from different DNS servers:**
```bash
# Google DNS
dig @8.8.8.8 _e5a93565e3c0c146efa9468fbe176157.dstreambolt.click CNAME

# Cloudflare DNS
dig @1.1.1.1 _e5a93565e3c0c146efa9468fbe176157.dstreambolt.click CNAME
```

### Issue: Browser still shows SSL error after certificate is issued

**Clear browser cache and try:**
```bash
# Test with curl
curl -I https://dstreambolt.click

# If still failing, check ALB listener certificate
aws elbv2 describe-listeners \
  --load-balancer-arn arn:aws:elasticloadbalancing:ap-south-1:771239567939:loadbalancer/app/dstreambolt-alb/755e9c234508892f \
  --region ap-south-1 \
  --query 'Listeners[?Port==`443`].Certificates[0].CertificateArn'
```

---

## 📞 **Support Information**

**Certificate ARN:**
```
arn:aws:acm:ap-south-1:771239567939:certificate/5933eefb-e9f4-4293-9ed3-c020ea1d78ab
```

**ALB ARN:**
```
arn:aws:elasticloadbalancing:ap-south-1:771239567939:loadbalancer/app/dstreambolt-alb/755e9c234508892f
```

**Region:** `ap-south-1` (Mumbai)

---

## 🎯 **Next Actions Required**

1. ⚠️  **ADD DNS CNAME RECORD** in HostAsia (see Step 2 above)
2. ⏳ Wait 10-15 minutes for validation
3. ✅ Run setup script again to attach certificate to ALB
4. 🎉 Access https://dstreambolt.click/

**The main blocking issue is the DNS validation record. Once you add the CNAME record in HostAsia, everything else will proceed automatically.**

---

## 📖 **Additional Resources**

- AWS ACM Documentation: https://docs.aws.amazon.com/acm/
- DNS Validation Guide: https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html
- ALB Certificate Setup: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-https-listener.html

