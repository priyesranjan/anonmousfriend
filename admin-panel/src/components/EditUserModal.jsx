import React, { useState } from 'react';
import { updateAdminUserWallet } from '../services/api';

const EditUserModal = ({ user, onSave, onClose }) => {
  const [formData, setFormData] = useState({
    display_name: user.display_name || '',
    gender: user.gender || '',
    city: user.city || '',
    country: user.country || '',
    avatar_url: user.avatar_url || '',
    wallet_balance: user.wallet_balance || 0,
  });

  const [walletLoading, setWalletLoading] = useState(false);

  const handleChange = (e) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();

    setWalletLoading(true);
    try {
      if (Number(formData.wallet_balance) !== Number(user.wallet_balance || 0)) {
        await updateAdminUserWallet(user.user_id, { balance: Number(formData.wallet_balance) });
      }
      onSave({ ...user, ...formData, wallet_balance: Number(formData.wallet_balance) });
    } catch (err) {
      console.error('Wallet update failed', err);
      // still proceed to save the rest
      onSave({ ...user, ...formData });
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white p-6 rounded-lg shadow-lg max-w-md w-full">
        <h2 className="text-xl font-bold mb-4">Edit User / God Mode</h2>
        <form onSubmit={handleSubmit} className="space-y-4">
          <label className="block">
            Display Name:
            <input
              type="text"
              name="display_name"
              value={formData.display_name}
              onChange={handleChange}
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>
          <label className="block">
            Wallet Balance (₹):
            <input
              type="number"
              name="wallet_balance"
              value={formData.wallet_balance}
              onChange={handleChange}
              className="w-full p-2 border border-gray-300 rounded mt-1 bg-yellow-50 focus:ring-yellow-500 font-bold"
            />
          </label>
          <label className="block">
            Gender:
            <input
              type="text"
              name="gender"
              value={formData.gender}
              onChange={handleChange}
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>
          <label className="block">
            City:
            <input
              type="text"
              name="city"
              value={formData.city}
              onChange={handleChange}
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>
          <label className="block">
            Country:
            <input
              type="text"
              name="country"
              value={formData.country}
              onChange={handleChange}
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>
          <label className="block">
            Avatar URL:
            <input
              type="text"
              name="avatar_url"
              value={formData.avatar_url}
              onChange={handleChange}
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>
          <div className="flex space-x-2 pt-2">
            <button disabled={walletLoading} type="submit" className="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600 disabled:opacity-50">
              {walletLoading ? 'Saving...' : 'Save'}
            </button>
            <button type="button" onClick={onClose} className="bg-gray-500 text-white px-4 py-2 rounded hover:bg-gray-600">Cancel</button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default EditUserModal;