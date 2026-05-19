import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';

export function Dashboard() {
  const navigate = useNavigate();
  const [displayName, setDisplayName] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data: userData } = await supabase.auth.getUser();
      const uid = userData.user?.id;
      if (!uid) return;
      const { data, error: dbErr } = await supabase
        .from('user_profiles')
        .select('display_name')
        .eq('id', uid)
        .single();
      if (cancelled) return;
      if (dbErr) setError(dbErr.message);
      else setDisplayName(data?.display_name ?? '');
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  async function handleLogout() {
    await supabase.auth.signOut();
    navigate('/login', { replace: true });
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-gray-50 p-4">
      <div className="w-full max-w-md space-y-4 rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
        <h1 className="text-xl font-semibold text-gray-900">
          {displayName ? `Welcome, ${displayName}` : 'Welcome'}
        </h1>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button
          onClick={handleLogout}
          className="rounded-md bg-gray-900 px-4 py-2 text-sm font-medium text-white hover:bg-gray-800"
        >
          Logout
        </button>
      </div>
    </div>
  );
}
