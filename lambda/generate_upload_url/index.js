const { S3Client } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { PutObjectCommand } = require('@aws-sdk/client-s3');
const crypto = require('crypto');

const s3Client = new S3Client({ region: process.env.AWS_REGION || 'us-east-1' });
const BUCKET_NAME = process.env.TODO_BUCKET_NAME;

// CORS headers
const CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
    'Access-Control-Allow-Methods': 'GET,OPTIONS',
    'Content-Type': 'application/json'
};

exports.handler = async (event) => {
    console.log('generate_upload_url Event:', JSON.stringify(event));

    try {
        // 從 Query String 取得額外參數 (非必要，但有助於限制副檔名等)
        const contentType = event.queryStringParameters?.contentType || 'image/jpeg';

        // 生成隨機的 UUID 作為檔名 (避免覆蓋)
        const fileId = crypto.randomUUID();
        const extension = contentType === 'image/png' ? 'png' : 'jpg';
        // 目標路徑：放在 raw/ 區
        const key = `raw/todo-images/${fileId}.${extension}`;

        const command = new PutObjectCommand({
            Bucket: BUCKET_NAME,
            Key: key,
            ContentType: contentType
        });

        // 產生 Presigned URL，預設 5 分鐘後過期 (300 秒)
        const uploadUrl = await getSignedUrl(s3Client, command, { expiresIn: 300 });

        console.log('Generated URL for Key:', key);

        return {
            statusCode: 200,
            headers: CORS_HEADERS,
            body: JSON.stringify({
                uploadUrl: uploadUrl,
                key: key,
                fileId: fileId
            })
        };
    } catch (error) {
        console.error('Error generating presigned URL:', error);
        return {
            statusCode: 500,
            headers: CORS_HEADERS,
            body: JSON.stringify({ error: 'Failed to generate upload URL', message: error.message })
        };
    }
};
