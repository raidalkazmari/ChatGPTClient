# AECGPT Backup 1.2 (build 5)

Installable companion to the existing AECGPT build 4. It intentionally uses distinct bundle identifiers so iOS/watchOS can keep both apps installed and keep their sessions/cache separate.

- iPhone: `com.aec.aecgpt.backup`
- Watch: `com.aec.aecgpt.backup.watchkitapp`
- Display name: **AECGPT Backup**

The Watch UI detects the first strong script in each paragraph and aligns Arabic/English text accordingly. Chat message image thumbnails transfer when their source permits canvas extraction. Attachments with a visible filename display a document/PDF card; PDF page contents are not rasterized for the Watch in this build.

The website's native iOS camera capture panel controls flash and shutter sound. If the flash shows Auto, select Off in the capture panel; iOS does not let this app force system shutter audio off.

This archive is unsigned. It must be signed and provisioned for the device with a sideloading tool. A user who has already installed build 4 should leave it in place and install this differently identified backup beside it.
