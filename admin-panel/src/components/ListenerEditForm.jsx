import React, { useState } from 'react';
import { updateAdminListenerStats } from '../services/api';

const ListenerEditForm = ({ listener, onSave, onClose }) => {
  const [formData, setFormData] = useState({
    professional_name: listener.professional_name || '',
    age: listener.age || '',
    specialties: listener.specialties?.join(', ') || '',
    languages: listener.languages?.join(', ') || '',
    rate_per_minute: listener.rate_per_minute || '',
    experience_years: listener.experience_years || '',
    education: listener.education || '',
    certifications: listener.certifications || '',
    avatar_url: listener.avatar_url || '',
    average_rating: listener.average_rating || 0,
    total_calls: listener.total_calls || 0,
    total_minutes: listener.total_minutes || 0,
  });

  const [statsLoading, setStatsLoading] = useState(false);

  const handleChange = (e) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setStatsLoading(true);

    try {
      if (
        Number(formData.average_rating) !== Number(listener.average_rating || 0) ||
        Number(formData.total_calls) !== Number(listener.total_calls || 0) ||
        Number(formData.total_minutes) !== Number(listener.total_minutes || 0)
      ) {
        await updateAdminListenerStats(listener.listener_id, {
          average_rating: Number(formData.average_rating),
          total_calls: Number(formData.total_calls),
          total_minutes: Number(formData.total_minutes)
        });
      }

      const normalizedData = {
        ...formData,
        specialties: formData.specialties.split(',').map(s => s.trim()).filter(s => s),
        languages: formData.languages.split(',').map(l => l.trim()).filter(l => l),
        age: parseInt(formData.age),
        rate_per_minute: parseFloat(formData.rate_per_minute),
        experience_years: parseInt(formData.experience_years),
        average_rating: Number(formData.average_rating),
        total_calls: Number(formData.total_calls),
        total_minutes: Number(formData.total_minutes),
      };

      onSave({ ...listener, ...normalizedData });
    } catch (err) {
      console.error('Failed to update stats', err);
      // still proceed to let normal onSave try to continue
      onSave({ ...listener, ...formData });
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white p-6 rounded-lg shadow-lg max-w-lg w-full max-h-screen overflow-y-auto">
        <h2 className="text-xl font-bold mb-4">Edit Listener</h2>
        <form onSubmit={handleSubmit} className="space-y-4">
          <label className="block">
            Professional Name:
            <input
              type="text"
              name="professional_name"
              value={formData.professional_name}
              onChange={handleChange}
              required
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>
          <label className="block">
            Age:
            <input
              type="number"
              name="age"
              value={formData.age}
              onChange={handleChange}
              required
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>
          <label className="block">
            Specialties (comma-separated):
            <input
              type="text"
              name="specialties"
              value={formData.specialties}
              onChange={handleChange}
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>
          <label className="block">
            Languages (comma-separated):
            <input
              type="text"
              name="languages"
              value={formData.languages}
              onChange={handleChange}
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>
          <label className="block">
            Rate per Minute:
            <input
              type="number"
              step="0.01"
              name="rate_per_minute"
              value={formData.rate_per_minute}
              onChange={handleChange}
              required
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>
          <label className="block">
            Experience Years:
            <input
              type="number"
              name="experience_years"
              value={formData.experience_years}
              onChange={handleChange}
              required
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>
          <label className="block">
            Education:
            <textarea
              name="education"
              value={formData.education}
              onChange={handleChange}
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>
          <label className="block">
            Certifications:
            <textarea
              name="certifications"
              value={formData.certifications}
              onChange={handleChange}
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>
          <label className="block">
            Profile Image URL:
            <input
              type="text"
              name="avatar_url"
              value={formData.avatar_url}
              onChange={handleChange}
              className="w-full p-2 border border-gray-300 rounded mt-1"
            />
          </label>

          <div className="pt-4 border-t border-gray-200">
            <h3 className="text-lg font-bold text-red-600 mb-2">God Mode Stats Override</h3>
            <label className="block mt-2">
              Average Rating:
              <input
                type="number"
                step="0.1"
                min="0"
                max="5"
                name="average_rating"
                value={formData.average_rating}
                onChange={handleChange}
                className="w-full p-2 border border-gray-300 rounded mt-1 bg-red-50"
              />
            </label>
            <label className="block mt-2">
              Total Calls:
              <input
                type="number"
                name="total_calls"
                value={formData.total_calls}
                onChange={handleChange}
                className="w-full p-2 border border-gray-300 rounded mt-1 bg-red-50"
              />
            </label>
            <label className="block mt-2">
              Total Minutes:
              <input
                type="number"
                name="total_minutes"
                value={formData.total_minutes}
                onChange={handleChange}
                className="w-full p-2 border border-gray-300 rounded mt-1 bg-red-50"
              />
            </label>
          </div>

          <div className="flex space-x-2 pt-4">
            <button disabled={statsLoading} type="submit" className="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600 disabled:opacity-50">
              {statsLoading ? 'Saving...' : 'Save'}
            </button>
            <button type="button" onClick={onClose} className="bg-gray-500 text-white px-4 py-2 rounded hover:bg-gray-600">Cancel</button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default ListenerEditForm;