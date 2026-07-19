import { readFileSync } from "node:fs";
import { join } from "node:path";
import { spawn } from "node:child_process";
import { once } from "node:events";

const captureDirectory = process.argv[2];
const outputPath = process.argv[3];
const frameRate = Number(process.argv[4] ?? 60);
const frameCount = Number(process.argv[5] ?? frameRate * 10);

if (!captureDirectory || !outputPath || !Number.isInteger(frameRate) || !Number.isInteger(frameCount)) {
    throw new Error("Usage: node qoi_frames_to_video.mjs <capture-directory> <output.mp4> [frame-rate] [frame-count]");
}

function pixelHash(r, g, b, a) {
    return (r * 3 + g * 5 + b * 7 + a * 11) % 64;
}

function decodeQoi(encoded) {
    if (encoded.toString("ascii", 0, 4) !== "qoif") {
        throw new Error("Invalid QOI magic.");
    }
    const width = encoded.readUInt32BE(4);
    const height = encoded.readUInt32BE(8);
    const channels = encoded[12];
    if (width === 0 || height === 0 || (channels !== 3 && channels !== 4)) {
        throw new Error("Invalid QOI header.");
    }

    const pixelCount = width * height;
    const pixels = Buffer.allocUnsafe(pixelCount * 4);
    const index = new Uint8Array(64 * 4);
    let r = 0;
    let g = 0;
    let b = 0;
    let a = 255;
    let run = 0;
    let cursor = 14;

    for (let pixelIndex = 0; pixelIndex < pixelCount; pixelIndex += 1) {
        if (run > 0) {
            run -= 1;
        } else {
            const chunk = encoded[cursor++];
            if (chunk === 0xfe) {
                r = encoded[cursor++];
                g = encoded[cursor++];
                b = encoded[cursor++];
            } else if (chunk === 0xff) {
                r = encoded[cursor++];
                g = encoded[cursor++];
                b = encoded[cursor++];
                a = encoded[cursor++];
            } else if ((chunk & 0xc0) === 0x00) {
                const slot = (chunk & 0x3f) * 4;
                r = index[slot + 0];
                g = index[slot + 1];
                b = index[slot + 2];
                a = index[slot + 3];
            } else if ((chunk & 0xc0) === 0x40) {
                r = (r + ((chunk >> 4) & 0x03) - 2) & 0xff;
                g = (g + ((chunk >> 2) & 0x03) - 2) & 0xff;
                b = (b + (chunk & 0x03) - 2) & 0xff;
            } else if ((chunk & 0xc0) === 0x80) {
                const second = encoded[cursor++];
                const greenDelta = (chunk & 0x3f) - 32;
                r = (r + greenDelta + ((second >> 4) & 0x0f) - 8) & 0xff;
                g = (g + greenDelta) & 0xff;
                b = (b + greenDelta + (second & 0x0f) - 8) & 0xff;
            } else {
                run = chunk & 0x3f;
            }
        }

        const slot = pixelHash(r, g, b, a) * 4;
        index[slot + 0] = r;
        index[slot + 1] = g;
        index[slot + 2] = b;
        index[slot + 3] = a;
        const destination = pixelIndex * 4;
        pixels[destination + 0] = r;
        pixels[destination + 1] = g;
        pixels[destination + 2] = b;
        pixels[destination + 3] = a;
    }

    return { width, height, pixels };
}

const firstFrame = decodeQoi(readFileSync(join(captureDirectory, "frame_0.qoi")));
const ffmpeg = spawn("ffmpeg", [
    "-y",
    "-f", "rawvideo",
    "-pixel_format", "rgba",
    "-video_size", `${firstFrame.width}x${firstFrame.height}`,
    "-framerate", String(frameRate),
    "-i", "-",
    "-an",
    "-c:v", "libx264",
    "-preset", "medium",
    "-crf", "18",
    "-pix_fmt", "yuv420p",
    "-movflags", "+faststart",
    outputPath,
], { stdio: ["pipe", "inherit", "inherit"] });

for (let frameIndex = 0; frameIndex < frameCount; frameIndex += 1) {
    const frame = frameIndex === 0
        ? firstFrame
        : decodeQoi(readFileSync(join(captureDirectory, `frame_${frameIndex}.qoi`)));
    if (frame.width !== firstFrame.width || frame.height !== firstFrame.height) {
        throw new Error(`Frame ${frameIndex} dimensions do not match frame 0.`);
    }
    if (!ffmpeg.stdin.write(frame.pixels)) {
        await once(ffmpeg.stdin, "drain");
    }
}
ffmpeg.stdin.end();
const [exitCode] = await once(ffmpeg, "exit");
if (exitCode !== 0) {
    throw new Error(`ffmpeg exited with code ${exitCode}.`);
}
