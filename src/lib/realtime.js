import { supabase, isSupabaseConfigured } from './supabase';

// Realtime is a transport for authorized database changes; row access remains controlled by RLS.
export function subscribeToConversation(conversationId, onMessage) {
  if (!isSupabaseConfigured || !supabase || !conversationId) return () => {};
  const channel = supabase.channel(`conversation:${conversationId}`)
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'messages',
      filter: `conversation_id=eq.${conversationId}`
    }, payload => onMessage?.(payload.new))
    .subscribe();
  return () => { supabase.removeChannel(channel); };
}

export async function sendMessage({ conversationId, body, messageType = 'text', mediaPath = null, replyTo = null, expiresAt = null }) {
  if (!isSupabaseConfigured || !supabase) throw new Error('Configura Supabase en el archivo .env para enviar mensajes reales.');
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError) throw authError;
  if (!user) throw new Error('Debes iniciar sesión para enviar mensajes.');
  const { data, error } = await supabase.from('messages').insert({
    conversation_id: conversationId,
    sender_id: user.id,
    body,
    message_type: messageType,
    media_path: mediaPath,
    reply_to: replyTo,
    expires_at: expiresAt
  }).select().single();
  if (error) throw error;
  return data;
}

export async function subscribeToNotifications(userId, onNotification) {
  if (!isSupabaseConfigured || !supabase || !userId) return () => {};
  const channel = supabase.channel(`notifications:${userId}`)
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'notifications', filter: `user_id=eq.${userId}`
    }, payload => onNotification?.(payload.new))
    .subscribe();
  return () => { supabase.removeChannel(channel); };
}
