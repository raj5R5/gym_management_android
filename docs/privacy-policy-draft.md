# MuscleDesk Privacy Policy

**Effective date: October 29, 2026.**

## 1. About this policy

MuscleDesk is a gym-management service used to maintain gym, member, trainer, membership and fee records. This policy describes the information handled by the MuscleDesk mobile app, its backend service and its public account-deletion page. “We”, “us” and “our” refer to the operator of MuscleDesk.

MuscleDesk is published and operated by **Raj**. For privacy and support inquiries, contact **pcterajbca7772@gmail.com**. MuscleDesk is initially offered in **India**. The Android app's package name is `com.semgroup.gymmanagement`.

A gym can enter information about people who do not themselves have a MuscleDesk login. The gym decides which records it enters and which staff it authorizes. Contact your gym about its use of your member or trainer record, or contact us about how the service handles information.

## 2. Information handled by MuscleDesk

- **Account and gym information:** Account email address, name, account status, password verification information, gym name, gym contact email/phone where supplied, optional owner phone/photo, gym timezone, and identifiers linking accounts to gyms and roles. Owner signup requires account and gym details; profile editing supports additional contact information.
- **Member and trainer records:** Member/trainer codes, first and last names, phone numbers, status and gym association. Optional fields include date of birth, gender, postal address, emergency-contact name/phone/relationship for members, and trainer specializations. Linked login-account identifiers and trainer/member assignments are stored where those features are used. An emergency contact's details may be entered by someone else.
- **Membership and financial records:** Plan names/descriptions, price and duration, membership start/end dates, renewal relationships, membership status, cancellation time/reason, notes, payment amounts and dates, payment method, transaction reference, outstanding balances and the account that recorded a payment. These are used for fee administration, dues and revenue summaries.
- **Optional photographs:** Photos deliberately selected through the camera or system photo picker for owner/member identification, local selection/recovery information, and server-side image references/revisions. Photographs can identify the person shown. MuscleDesk does not use facial recognition or biometric matching.
- **Authentication and recovery records:** Passwords provided for signup, sign-in or verification, password hashes, sessions/tokens, and registration/payment/renewal/photo operation records and receipts used to prevent duplicate or lost operations. Some of these operation records contain personal or financial fields entered for the original operation. Password recovery stores an account-linked digest of the recovery code, a digest of the registered email, a credential revision, an expiry and a use time; the code itself is sent by email and is not stored.
- **Deletion requests:** The requesting account reference, request reference, status and timestamps. The password used to verify an in-app or web request is not stored. While a request is being carried out we also keep the processing stage, timestamps and the outcome chosen for each gym, plus your account email address in encrypted form until the completion email has been sent. If you email a request, your email address and message are held in our Gmail mailbox.
- **Technical and operational information:** Server-generated record/request identifiers, creation/update times, request method/route template, response status, processing time, safe error categories and security events. Some security events include internal account/session or gym/resource identifiers. Network infrastructure processes connection information such as IP addresses, and hosting, database and provider logs may contain additional technical information.

Free-text notes, descriptions and cancellation reasons contain what the person entering them supplies. Avoid entering unnecessary sensitive information, payment credentials or passwords into these fields. The app does not collect card numbers, CVVs, bank logins or payment-gateway details: a recorded payment method/reference is a gym bookkeeping record, not an in-app transfer of money.

Attendance and branch management are retired features. If a gym used earlier versions, historical attendance or branch-related records may remain with that gym's records.

## 3. Where the information comes from and why it is used

Information comes from account owners, authorized gym staff, people using account/profile features, deliberately selected photos, and the operation of the service. We use it to provide MuscleDesk's functions:

- Create and authenticate accounts, restore sessions, enforce gym/role permissions and prevent unauthorized access.
- Maintain member/trainer profiles and assignments; identify records and show the profile images a user selected.
- Administer plans, memberships, expiry, renewal and cancellation, and show membership eligibility and status.
- Record fees and payment history; calculate dues and revenue; prevent duplicate financial operations and recover interrupted requests.
- Keep operational and security records, diagnose failures, send account-recovery and account-deletion emails, and handle support and deletion requests.

MuscleDesk is not a medical-record, workout-sensor or exercise-tracking product. It does not use Health Connect/HealthKit, precise location, phone-contact import, SMS, microphone recording, advertising identifiers or behavioral analytics. Postal addresses entered in profiles are separate from device location.

We process personal data only to provide the gym-management service. We do not sell personal information, do not keep separate personal or spreadsheet copies of customer data, and do not use customer data for unrelated personal purposes. Information is stored in and processed by the service providers described in section 5 as part of running the service. A gym's own exports or disclosures of its records outside MuscleDesk are that gym's responsibility.

## 4. Device storage, photos and permissions

The app stores the rotating sign-in refresh credential in platform secure storage. Access tokens are held in memory. Registration and financial recovery records use scoped secure storage. These recovery records may remain until their operation has been confirmed and acknowledged or resolved, so that restarting or signing out does not cause duplicate registration or payment collection.

Photo selections and recovery metadata are kept separately in the app's private application-support files, which are not the credential secure store. Original selected copies or picker/OS caches may contain metadata. Normal photo completion/discard removes the app's staged copy; interrupted operations or cleanup failures can keep it for recovery.

Photos are optional. Camera or photo-library access starts only when you choose that feature, subject to the device's picker and permission controls. The app does not scan the photo library in the background. Without a photo, the initials fallback is shown. Device permissions can be managed in system settings.

The backend validates the selected image, re-encodes it to a resized JPEG and uploads the processed copy to Cloudinary as an authenticated asset. The processed copy does not keep the original's EXIF location metadata or embedded profiles. Images are delivered through the protected API. When a photo is replaced or removed, the old copy is deleted from Cloudinary; a failed deletion is retried automatically.

Signing out clears the sign-in credential; it does not erase the gym's server records or necessarily remove unresolved local recovery data. Uninstalling the app is not an account-deletion request.

## 5. Access to data and service providers

Gym records can be accessed through the service by authenticated people whose gym, role or assignment permits it. The operator may access information where needed to support and operate the service, including to carry out deletion requests.

MuscleDesk uses these service providers:

- **API hosting:** The backend runs on a virtual private server provided by Hostinger, where it processes account, gym and operation data.
- **Database:** MongoDB Atlas stores the application records.
- **Photos:** Cloudinary stores and serves processed owner/member photos and their asset identifiers as authenticated assets.
- **Email:** Gmail sends account-recovery codes, password-change notices and account-deletion emails from pcterajbca7772@gmail.com, and holds support and deletion-request correspondence sent to that address. No email contains a password.
- **Device and browser services:** The operating system provides secure storage, app-private storage and camera/photo selection. Opening a privacy or deletion link launches a browser, and the visited website processes that request.

These providers process information under their own terms and in the locations their services and our account settings use; we do not state specific processing locations. MuscleDesk includes no advertising or third-party analytics SDK. We do not share information with anyone other than these providers and the authorized people described in this section.

The mobile app signs in with tokens rather than browser cookies. The backend can also issue a secure, HttpOnly refresh cookie to a web client that uses that sign-in method. The public privacy and deletion pages set no cookies and load no analytics scripts.

## 6. Security

The app connects only to the MuscleDesk HTTPS API. The backend hashes passwords with Argon2id, stores digests rather than plaintext refresh tokens, checks authentication and gym permissions on every protected request, and supports token rotation and revocation. The app keeps its stored refresh credential in platform secure storage.

Application diagnostics are designed not to log passwords, credentials or request bodies. The backend's request logger omits client addresses and raw URLs/bodies; security-event logs can contain internal identifiers. Hosting, database and provider logs are kept under those providers' settings.

These controls reduce risk but cannot guarantee absolute security. MuscleDesk is not end-to-end encrypted: the backend and its service providers process data to provide the functions described here.

## 7. Retention and deletion

We keep information only for as long as it serves the purpose it was collected for:

- **Account information** is kept while the account exists, and deleted when a valid deletion request is fulfilled (section 8).
- **Gym records** — members, trainers, plans, memberships, payments and photos — are kept while the gym uses MuscleDesk, because they are that gym's operating records. Authorized gym staff can change or delete them, and they are deleted if the gym's owner closes the gym. No fixed retention period applies.
- **Authentication, activation and recovery records** expire automatically and are then removed by database cleanup.
- **Operation and idempotency records** are kept to prevent duplicate registrations, payments and renewals; those linked to a deleted account are deleted with it.

When a deletion request is fulfilled, only the following are kept, each for the stated reason:

- **Records of a gym that continues to operate:** a member or trainer record about you that such a gym entered, and payments you recorded as that gym's staff, stay with that gym as its business records. The link to your deleted login is removed. Contact that gym about those records.
- **A minimal deletion record:** the request reference, internal account and gym identifiers, processing stages and timestamps, without your email address, name or password. It records that the request was fulfilled and allows the deletion to be applied again if the database is ever restored from a backup. It is removed once no backup taken before the deletion remains.
- **Backups and logs:** copies may remain in database backups and in server and provider logs until they expire under the provider's settings. Backups are used only to restore the service, not for normal operation.
- **Correspondence:** emails you send to the support address are kept in that mailbox while needed to handle your request.

We do not claim a legal obligation to keep any of this information.

## 8. Your choices and account deletion

Owners can edit their profile and gym records and manage photos in the app. A member or trainer whose information was entered by a gym should contact that gym about access, correction or removal of their record. For other privacy requests, contact us using the address in section 11; your rights depend on the law that applies to you.

You can request deletion of your account and its associated personal data:

- **In the app:** open **More → Request account deletion** and confirm with your current password.
- **On the web, without the app:** use the [account-deletion page](https://gym-api.semgroup.in/account-deletion) with your account email and current password.
- **By email, if you cannot sign in:** email pcterajbca7772@gmail.com from any address, stating the email address of your MuscleDesk account. We reply to the account's email address and act only after you confirm the request from it. If you have only forgotten your password, you can instead use **Recover access** on the app's sign-in screen and then request deletion. Do not send passwords, recovery codes or identity/payment documents by email.

The operator, Raj, reviews and carries out deletion requests manually:

1. **Review.** We check the request and the gyms your account can access. Your account keeps working until deletion is carried out.
2. **Gyms you own.** If other active owners run the gym, you leave it and they keep it. If you are the only owner, we email your account address to ask whether to close the gym or to make a staff member an owner first. **Closing a gym permanently deletes the gym and all of its records**, including members, trainers, plans, memberships, payments, assignments, photos and historical attendance/branch records, and removes everyone's access to it. We close a gym only after you confirm closure in writing. Keep any records you need before closing; we do not keep a copy.
3. **Deletion.** Your login account, sessions, recovery and activation records, owner profiles and their photos, and your own operation records are deleted. Photos are deleted from Cloudinary, with automatic retries if a deletion fails.
4. **Completion.** Your request is marked complete, and a completion email is sent to your account address, only after the deletion has actually been carried out and checked. Until then the app shows the request as received or under review.

The records kept after deletion are described in section 7. Signing out or uninstalling the app does not delete your account.

## 9. Children and age-related information

MuscleDesk is intended for adult account holders. Owner signup requires a declaration that the account holder is an adult; this is a declaration, not age verification. Under-18 member records are not supported until guardian authorization and related controls exist: the service rejects a date of birth under 18 for new members, and blocks profile changes, new photo uploads and member-account activation for members whose recorded date of birth shows they are under 18. Existing records remain readable, and their photos can be removed. Date of birth is optional, and a missing date of birth is not treated as proof of adulthood.

## 10. Locations, applicable rights and changes

MuscleDesk is offered in India. The service providers in section 5 may process data in locations other than where the gym or person is located.

Depending on the law that applies to you, you may have rights to access, correct or delete your personal data or to raise a concern. Contact us at the address in section 11 and we will respond to your request.

When this policy changes, the updated version is published at the address below with a new effective date.

## 11. Privacy contact

**Operator/publisher: Raj.**

**Privacy and support contact: pcterajbca7772@gmail.com.** Do not send passwords or authentication tokens to this address.

**Policy address: https://gym-api.semgroup.in/privacy-policy.**

**Effective date: October 29, 2026.**
