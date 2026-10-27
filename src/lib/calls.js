import { supabase, isSupabaseConfigured } from './supabase';

/** WebRTC carries the actual audio/video. Supabase Realtime is signaling only. */
export async function createCallSignalChannel(callId, onSignal) {
  if (!isSupabaseConfigured || !supabase) throw new Error('Supabase no está configurado.');
  const channel = supabase.channel(`call:${callId}`, { config: { broadcast: { self: false } } });
  channel.on('broadcast', { event: 'signal' }, ({ payload }) => onSignal?.(payload));
  await channel.subscribe();
  return {
    send: payload => channel.send({ type: 'broadcast', event: 'signal', payload }),
    close: () => supabase.removeChannel(channel)
  };
}

export async function requestMedia({ video = true, audio = true } = {}) {
  if (!navigator.mediaDevices?.getUserMedia) throw new Error('Este dispositivo o navegador no permite acceder a la cámara o al micrófono.');
  return navigator.mediaDevices.getUserMedia({ video, audio });
}

export function createPeerConnection({ iceServers } = {}) {
  const configured = iceServers || [
    { urls: (import.meta.env.VITE_STUN_URL || 'stun:stun.l.google.com:19302') },
    ...(import.meta.env.VITE_TURN_URL ? [{
      urls: import.meta.env.VITE_TURN_URL,
      username: import.meta.env.VITE_TURN_USERNAME || '',
      credential: import.meta.env.VITE_TURN_CREDENTIAL || ''
    }] : [])
  ];
  return new RTCPeerConnection({ iceServers: configured, bundlePolicy: 'max-bundle' });
}

/**
 * Applies a visual filter to the outgoing video track itself, so a WebRTC peer receives the effect.
 * Call stop() on the returned handle when the call ends. Requires HTTPS and browser canvas captureStream.
 */
export async function createFilteredVideoStream(inputStream, filter = 'none') {
  const videoTrack = inputStream.getVideoTracks()[0];
  if (!videoTrack) throw new Error('No hay una pista de vídeo disponible.');
  if (filter === 'none') return { stream: inputStream, stop: () => {} };
  if (typeof document === 'undefined') throw new Error('El filtro necesita un navegador.');
  const video = document.createElement('video');
  video.muted = true; video.playsInline = true; video.srcObject = new MediaStream([videoTrack]);
  await video.play();
  const canvas = document.createElement('canvas');
  const width = videoTrack.getSettings().width || 1280;
  const height = videoTrack.getSettings().height || 720;
  canvas.width = width; canvas.height = height;
  const ctx = canvas.getContext('2d');
  if (!ctx || !canvas.captureStream) throw new Error('Este navegador no permite procesar el vídeo de salida.');
  const filters = {
    emerald: 'saturate(1.25) hue-rotate(15deg) contrast(1.08)',
    mono: 'grayscale(1) contrast(1.12)',
    warm: 'sepia(.22) saturate(1.25) contrast(1.04)',
    cool: 'saturate(1.12) hue-rotate(175deg)',
    glow: 'brightness(1.12) saturate(1.3) contrast(1.05)'
  };
  let frame = 0;
  let stopped = false;
  const draw = () => {
    if (stopped) return;
    ctx.filter = filters[filter] || 'none';
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
    frame = requestAnimationFrame(draw);
  };
  draw();
  const processed = canvas.captureStream(30);
  inputStream.getAudioTracks().forEach(track => processed.addTrack(track));
  return {
    stream: processed,
    stop: () => { stopped = true; cancelAnimationFrame(frame); processed.getVideoTracks().forEach(t => t.stop()); video.pause(); video.srcObject = null; }
  };
}
