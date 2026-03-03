import React, { useState, useEffect } from 'react';
import { getNewbies, sendMarketingNotification } from '../services/api';
import SkeletonLoader from '../components/SkeletonLoader';
import toast from 'react-hot-toast';

const Marketing = () => {
    const [newbies, setNewbies] = useState([]);
    const [loading, setLoading] = useState(true);
    const [sending, setSending] = useState(false);
    const [error, setError] = useState(null);

    const [title, setTitle] = useState("Exclusive Offer!");
    const [body, setBody] = useState("Recharge ₹50 today and get 10 free minutes!");

    useEffect(() => {
        fetchNewbies();
    }, []);

    const fetchNewbies = async () => {
        try {
            const res = await getNewbies();
            setNewbies(res.data || []);
            toast.success('Marketing audience loaded');
        } catch (error) {
            setError('Failed to fetch newbies');
            toast.error('Failed to load marketing audience');
        } finally {
            setLoading(false);
        }
    };

    const handleSendNotification = async (e) => {
        e.preventDefault();
        if (!title || !body) {
            toast.error('Please fill in both title and body');
            return;
        }

        if (newbies.length === 0) {
            toast.error('No users in audience to send to!');
            return;
        }

        setSending(true);
        try {
            await sendMarketingNotification({ title, body });
            toast.success(`Notification sent successfully to ${newbies.length} users!`);
            setTitle('');
            setBody('');
        } catch (error) {
            toast.error('Failed to send notifications');
        } finally {
            setSending(false);
        }
    };

    if (loading) return <SkeletonLoader type="table" />;

    return (
        <div className="min-h-screen bg-gray-50 dark:bg-gray-900 p-6">
            <div className="max-w-7xl mx-auto">
                <div className="mb-8">
                    <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">Marketing Dashboard</h1>
                    <p className="text-gray-600 dark:text-gray-400">
                        Target users who have downloaded the app but never recharged (Newbies).
                    </p>
                </div>

                <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">

                    {/* Campaign Form */}
                    <div className="lg:col-span-1">
                        <div className="bg-white dark:bg-gray-800 rounded-xl shadow-sm border border-gray-200 dark:border-gray-700 p-6">
                            <h2 className="text-xl font-bold text-gray-900 dark:text-white mb-4">New Campaign</h2>
                            <form onSubmit={handleSendNotification} className="space-y-4">
                                <div>
                                    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                                        Notification Title
                                    </label>
                                    <input
                                        type="text"
                                        value={title}
                                        onChange={(e) => setTitle(e.target.value)}
                                        className="w-full px-4 py-2 bg-gray-50 dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 text-gray-900 dark:text-white"
                                        placeholder="e.g. Flash Sale!"
                                    />
                                </div>
                                <div>
                                    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                                        Notification Body
                                    </label>
                                    <textarea
                                        value={body}
                                        onChange={(e) => setBody(e.target.value)}
                                        rows={4}
                                        className="w-full px-4 py-2 bg-gray-50 dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 text-gray-900 dark:text-white"
                                        placeholder="e.g. Recharge now and get 10 free minutes!"
                                    />
                                </div>
                                <button
                                    type="submit"
                                    disabled={sending || newbies.length === 0}
                                    className="w-full py-3 px-4 bg-gradient-to-r from-blue-600 to-purple-600 hover:from-blue-700 hover:to-purple-700 text-white rounded-lg font-medium shadow-md transition-all disabled:opacity-50"
                                >
                                    {sending ? 'Sending...' : `Send to ${newbies.length} Users`}
                                </button>
                            </form>
                        </div>
                    </div>

                    {/* Audience List */}
                    <div className="lg:col-span-2">
                        <div className="bg-white dark:bg-gray-800 rounded-xl shadow-sm border border-gray-200 dark:border-gray-700 overflow-hidden">
                            <div className="p-6 border-b border-gray-200 dark:border-gray-700 flex justify-between items-center">
                                <h2 className="text-xl font-bold text-gray-900 dark:text-white">Eligible Audience</h2>
                                <span className="bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400 py-1 px-3 rounded-full text-sm font-medium">
                                    {newbies.length} Users
                                </span>
                            </div>
                            <div className="overflow-x-auto">
                                <table className="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
                                    <thead className="bg-gray-50 dark:bg-gray-700/50">
                                        <tr>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">User</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">Phone</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">Joined At</th>
                                        </tr>
                                    </thead>
                                    <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
                                        {newbies.length > 0 ? (
                                            newbies.map((user) => (
                                                <tr key={user.user_id}>
                                                    <td className="px-6 py-4 whitespace-nowrap">
                                                        <div className="text-sm font-medium text-gray-900 dark:text-white">{user.display_name || 'N/A'}</div>
                                                        <div className="text-sm text-gray-500 dark:text-gray-400">ID: {user.user_id}</div>
                                                    </td>
                                                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-300">
                                                        {user.phone_number || 'N/A'}
                                                    </td>
                                                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-300">
                                                        {new Date(user.created_at).toLocaleDateString()}
                                                    </td>
                                                </tr>
                                            ))
                                        ) : (
                                            <tr>
                                                <td colSpan="3" className="px-6 py-8 text-center text-gray-500 dark:text-gray-400">
                                                    No eligible non-recharged users found.
                                                </td>
                                            </tr>
                                        )}
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default Marketing;
