# CloudFront returns 403 for newly-uploaded S3 objects

## Symptom
- CloudFront distribution `EQC6PDRS7IRAH` (domain `dan5qol6gum18.cloudfront.net`)
- Origin: S3 bucket `cowparadise-cdn-assets-423623846645-us-east-1-an` (us-east-1)
- **Objects uploaded before 2026-05-27 are served correctly (HTTP 200)**
- **Objects uploaded on or after 2026-05-27, via `aws s3 cp` or `s3api put-object`, return 403** with `Server: AmazonS3`, `X-Cache: Error from cloudfront` — CloudFront forwards to S3 and S3 declines.
- Direct anonymous GET to the S3 REST endpoint (`https://<bucket>.s3.us-east-1.amazonaws.com/<key>`) returns **200** for the same new objects.

## Environment
| | |
|---|---|
| Account | `423623846645` (root user; no AWS Organizations) |
| CloudFront distribution | `EQC6PDRS7IRAH`, status `Deployed` |
| OAC | `E3CI8KTU6KRK5S`, SigningProtocol=sigv4, SigningBehavior=always, OriginType=s3, currently attached |
| Bucket Object Ownership | `BucketOwnerEnforced` (ACLs disabled) |
| Bucket Block Public Access | all four flags = false |
| Bucket default encryption | SSE-S3 (AES256), BucketKeyEnabled=true |
| Bucket policy | Two statements (see below): public-read for `Principal: "*"` AND CF service principal with `aws:SourceArn` matching the distribution |

## Bucket policy (current)
```json
{
  "Version": "2012-10-17",
  "Id": "CowParadiseAssetsPolicy",
  "Statement": [
    {"Sid": "AllowPublicRead", "Effect": "Allow", "Principal": "*", "Action": "s3:GetObject",
     "Resource": "arn:aws:s3:::cowparadise-cdn-assets-423623846645-us-east-1-an/*"},
    {"Sid": "AllowCloudFrontServicePrincipal", "Effect": "Allow",
     "Principal": {"Service": "cloudfront.amazonaws.com"}, "Action": "s3:GetObject",
     "Resource": "arn:aws:s3:::cowparadise-cdn-assets-423623846645-us-east-1-an/*",
     "Condition": {"ArnLike": {"AWS:SourceArn": "arn:aws:cloudfront::423623846645:distribution/EQC6PDRS7IRAH"}}}
  ]
}
```

## What works
- `aws s3 cp s3://<bucket>/media/<key> -` (CLI download) — works for new objects (root creds)
- `curl https://<bucket>.s3.us-east-1.amazonaws.com/media/<key>` (direct REST endpoint, anonymous) — works for new objects (200)
- `curl https://dan5qol6gum18.cloudfront.net/images/games/cowrun.webp` (CloudFront, old object) — works (200)

## What fails
- `curl https://dan5qol6gum18.cloudfront.net/media/<key>` (CloudFront, new object) — **403 Forbidden**, even with cache invalidation `/*`

## What has been ruled out
- ACLs (BucketOwnerEnforced disables them; old vs new objects have identical `get-object-acl` output)
- Object encryption (both old and new are SSE-S3 AES256; tested upload with `--no-bucket-key-enabled` — same 403)
- Object versioning (versioning enabled on bucket; new objects are latest version)
- CloudFront cache (invalidated `/*` multiple times, completed status)
- CloudFront Functions / Lambda@Edge (none configured)
- CustomErrorResponses (none)
- WebACL/WAF (response is from S3, not WAF)
- GeoRestriction (none)
- S3 Object Lock (not configured)
- S3 Replication (not configured)
- Origin Path or custom headers (none)
- Organization SCPs (account not in an org)
- Bucket-level BPA (all four = false)
- Account-level BPA (no configuration exists)

## Hypothesis
Old objects were originally uploaded before BucketOwnerEnforced was applied, likely with `public-read` ACL grants that survive at the object level (despite head-object/get-object-acl reporting only owner FULL_CONTROL — possibly hidden grant state). New objects, written under BucketOwnerEnforced, must rely purely on the bucket policy — and for some reason the CloudFront OAC-signed request isn't matching either statement at evaluation time despite both being correctly formed.

## Asks
1. Why does the bucket policy's `AllowCloudFrontServicePrincipal` statement (with the correct `aws:SourceArn`) not grant access to objects uploaded under BucketOwnerEnforced, when the same distribution + OAC successfully reads objects created before the ownership change?
2. Is there an internal cache or propagation delay between OAC re-association and bucket policy re-evaluation? The distribution shows `Deployed` for >10 minutes with no change in behavior.
3. Is there any hidden ACL/owner state on the legacy objects that CloudFront is exploiting, that new objects lack?
