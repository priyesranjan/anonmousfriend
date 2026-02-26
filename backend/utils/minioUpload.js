import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import dotenv from 'dotenv';
import path from 'path';

// ensure env variables are loaded
dotenv.config({ path: path.join(process.cwd(), '.env') });

const s3Client = new S3Client({
  endpoint: process.env.CLOUDFLARE_R2_ENDPOINT || 'https://<ACCOUNT_ID>.r2.cloudflarestorage.com',
  region: process.env.CLOUDFLARE_R2_REGION || 'auto',
  credentials: {
    accessKeyId: process.env.CLOUDFLARE_R2_ACCESS_KEY || 'r2_access_key',
    secretAccessKey: process.env.CLOUDFLARE_R2_SECRET_KEY || 'r2_secret_key',
  },
  forcePathStyle: true, // Sometimes required for S3 compatible APIs
});

const BUCKET_NAME = process.env.CLOUDFLARE_R2_BUCKET_NAME || 'callto-bucket';

/**
 * Uploads a file buffer to Cloudflare R2 (S3 compatible)
 * @param {Buffer} buffer File buffer
 * @param {string} originalName Original file name
 * @param {string} mimeType File mime type
 * @param {string} folder Target folder path
 * @returns {Promise<Object>} Object containing secure_url and public_id
 */
export const uploadToMinio = async (buffer, originalName, mimeType, folder = 'uploads') => {
  try {
    const ext = path.extname(originalName) || '';
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    const fileName = `${folder}/${uniqueSuffix}${ext}`;

    const command = new PutObjectCommand({
      Bucket: BUCKET_NAME,
      Key: fileName,
      Body: buffer,
      ContentType: mimeType,
    });

    await s3Client.send(command);

    // Generate the public URL (assuming Cloudflare R2 public bucket routing is enabled)
    // Format: https://pub-<hash>.r2.dev/<file-path> or your custom domain https://s3.call.appdost.com/<file-path>
    const secureUrl = `${process.env.CLOUDFLARE_R2_PUBLIC_URL || 'https://s3.call.appdost.com'}/${fileName}`;

    return {
      secure_url: secureUrl,
      public_id: fileName,
      format: ext.replace('.', ''),
      duration: null // MinIO doesn't parse audio duration automatically like Cloudinary
    };
  } catch (error) {
    console.error('Cloudflare R2 upload error:', error);
    throw error;
  }
};

export default s3Client;
