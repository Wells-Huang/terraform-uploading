const { S3Client, GetObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');
const sharp = require('sharp');
const path = require('path');

const s3Client = new S3Client({ region: process.env.AWS_REGION || 'us-east-1' });

exports.handler = async (event) => {
    console.log('crop_image Event triggered by S3:', JSON.stringify(event, null, 2));

    try {
        // 從 S3 Event 中取得 Bucket 和 Key
        const record = event.Records[0];
        const bucket = record.s3.bucket.name;
        // Key 可能會有 URL encoded 的字元 (如空白變為 +)
        const srcKey = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));

        // 檢查前綴，只處理 raw/ 開頭的檔案
        if (!srcKey.startsWith('raw/')) {
            console.log(`Skipping object ${srcKey}. It is not in the 'raw/' prefix.`);
            return;
        }

        console.log(`Processing image from bucket: ${bucket}, key: ${srcKey}`);

        // 1. 從 S3 取得原始圖片
        const getCommand = new GetObjectCommand({
            Bucket: bucket,
            Key: srcKey
        });
        const getResult = await s3Client.send(getCommand);

        // 將 Stream 轉為 Buffer 供 sharp 使用
        const chunks = [];
        for await (const chunk of getResult.Body) {
            chunks.push(chunk);
        }
        const imageBuffer = Buffer.concat(chunks);

        // 2. 獲取圖片原始大小
        const metadata = await sharp(imageBuffer).metadata();
        console.log(`Original image metadata: ${metadata.width}x${metadata.height}`);

        // 找出短邊作為正方形的邊長
        const size = Math.min(metadata.width, metadata.height);

        // 3. 進行中心正方形裁切
        // sharp.resize({ width, height, fit: 'cover' }) 會自動預設為中心裁切
        const croppedBuffer = await sharp(imageBuffer)
            .resize({
                width: size,
                height: size,
                fit: 'cover',
                position: 'center'
            })
            .toBuffer();

        // 4. 定義目標路徑：將 'raw/' 替換為 'processed/'
        const dstKey = srcKey.replace(/^raw\//, 'processed/');

        console.log(`Uploading cropped image to: ${dstKey}`);

        // 5. 上傳回 S3 (存放到 processed 目錄)
        const putCommand = new PutObjectCommand({
            Bucket: bucket,
            Key: dstKey,
            Body: croppedBuffer,
            ContentType: getResult.ContentType || 'image/jpeg'
        });

        await s3Client.send(putCommand);

        console.log(`Successfully cropped and uploaded image to ${dstKey}`);

        // (可選) 在這裡你可以呼叫 S3 API 刪除原圖 (srcKey) 來節省空間 
        // 但安全起見可以先保留或藉由 S3 Lifecycle 處理

        return {
            statusCode: 200,
            body: JSON.stringify('Crop successful.')
        };
    } catch (error) {
        console.error('Error in crop_image lambda:', error);
        throw error;
    }
};
