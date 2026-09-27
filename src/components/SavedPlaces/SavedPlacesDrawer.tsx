import React, { useState } from 'react';
import { SavedPlace, Coordinate } from '../../types';
import { X, Bookmark, Clock, Trash2, Plus, Navigation, MapPin } from 'lucide-react';

interface SavedPlacesDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  savedPlaces: SavedPlace[];
  onTeleportTo: (coord: Coordinate) => void;
  onSavePlace: (name: string, coord: Coordinate, category: SavedPlace['category']) => void;
  onDeletePlace: (id: string) => void;
  currentLocation: Coordinate;
}

export const SavedPlacesDrawer: React.FC<SavedPlacesDrawerProps> = ({
  isOpen,
  onClose,
  savedPlaces,
  onTeleportTo,
  onSavePlace,
  onDeletePlace,
  currentLocation,
}) => {
  const [activeTab, setActiveTab] = useState<'favorites' | 'recents'>('favorites');
  const [newPlaceName, setNewPlaceName] = useState('');
  const [isAdding, setIsAdding] = useState(false);

  if (!isOpen) return null;

  const filteredPlaces = savedPlaces.filter((p) =>
    activeTab === 'favorites' ? p.category === 'favorite' || p.category === 'custom' : p.category === 'recent'
  );

  const handleSaveCurrent = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newPlaceName.trim()) return;
    onSavePlace(newPlaceName.trim(), currentLocation, 'favorite');
    setNewPlaceName('');
    setIsAdding(false);
  };

  return (
    <div className="fixed inset-0 z-[600] flex justify-end bg-black/50 backdrop-blur-sm animate-in fade-in duration-150">
      <div className="w-full max-w-md bg-slate-900 border-l border-white/10 h-full flex flex-col shadow-2xl animate-in slide-in-from-right duration-200">
        {/* Header */}
        <div className="flex items-center justify-between p-5 border-b border-white/10 bg-slate-950/50">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-amber-500/20 text-amber-400 flex items-center justify-center border border-amber-500/30">
              <Bookmark className="w-4 h-4" />
            </div>
            <div>
              <h2 className="text-base font-bold text-white tracking-tight">Saved & Recents</h2>
              <p className="text-xs text-slate-400">Quick teleport bookmark directory</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-xl hover:bg-white/10 text-slate-400 hover:text-white transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Tab Switcher */}
        <div className="flex p-3 bg-slate-950/80 border-b border-white/5 gap-2">
          <button
            onClick={() => setActiveTab('favorites')}
            className={`flex-1 flex items-center justify-center gap-1.5 py-2 rounded-xl text-xs font-semibold transition-all ${
              activeTab === 'favorites'
                ? 'bg-amber-500 text-slate-950 shadow-md shadow-amber-500/20 font-bold'
                : 'text-slate-400 hover:text-white hover:bg-white/5'
            }`}
          >
            <Bookmark className="w-3.5 h-3.5" />
            <span>Favorites ({savedPlaces.filter((p) => p.category !== 'recent').length})</span>
          </button>
          <button
            onClick={() => setActiveTab('recents')}
            className={`flex-1 flex items-center justify-center gap-1.5 py-2 rounded-xl text-xs font-semibold transition-all ${
              activeTab === 'recents'
                ? 'bg-cyan-500 text-slate-950 shadow-md shadow-cyan-500/20 font-bold'
                : 'text-slate-400 hover:text-white hover:bg-white/5'
            }`}
          >
            <Clock className="w-3.5 h-3.5" />
            <span>Recents ({savedPlaces.filter((p) => p.category === 'recent').length})</span>
          </button>
        </div>

        {/* Add current location prompt */}
        {activeTab === 'favorites' && (
          <div className="p-4 border-b border-white/5 bg-slate-950/40">
            {!isAdding ? (
              <button
                onClick={() => setIsAdding(true)}
                className="w-full py-2.5 px-3 bg-slate-800 hover:bg-slate-700 text-cyan-400 text-xs font-semibold rounded-xl flex items-center justify-center gap-1.5 border border-cyan-500/20 transition-all"
              >
                <Plus className="w-4 h-4" />
                <span>Bookmark Current Location</span>
              </button>
            ) : (
              <form onSubmit={handleSaveCurrent} className="space-y-2">
                <input
                  type="text"
                  autoFocus
                  value={newPlaceName}
                  onChange={(e) => setNewPlaceName(e.target.value)}
                  placeholder="E.g. Home, Favorite Gym, Eiffel Tower..."
                  className="w-full bg-slate-950 border border-cyan-500/40 rounded-xl px-3 py-2 text-xs text-white placeholder-slate-500 focus:outline-none"
                />
                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={() => setIsAdding(false)}
                    className="flex-1 py-1.5 rounded-lg bg-slate-800 text-slate-400 text-xs hover:bg-slate-700"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    className="flex-1 py-1.5 rounded-lg bg-cyan-500 hover:bg-cyan-600 text-white font-semibold text-xs shadow-md"
                  >
                    Save
                  </button>
                </div>
              </form>
            )}
          </div>
        )}

        {/* Places List */}
        <div className="flex-1 overflow-y-auto p-4 space-y-2.5 custom-scrollbar">
          {filteredPlaces.length === 0 ? (
            <div className="text-center py-12 text-slate-500 text-xs">
              {activeTab === 'favorites' ? 'No saved favorites yet.' : 'No recent teleport history.'}
            </div>
          ) : (
            filteredPlaces.map((place) => (
              <div
                key={place.id}
                className="p-3.5 rounded-2xl bg-slate-950/60 border border-white/5 hover:border-white/10 flex items-center justify-between gap-3 group transition-all"
              >
                <div className="flex items-center gap-3 overflow-hidden">
                  <div
                    className={`w-9 h-9 rounded-xl flex items-center justify-center shrink-0 ${
                      place.category === 'recent'
                        ? 'bg-cyan-500/10 text-cyan-400 border border-cyan-500/20'
                        : 'bg-amber-500/10 text-amber-400 border border-amber-500/20'
                    }`}
                  >
                    {place.category === 'recent' ? <Clock className="w-4 h-4" /> : <MapPin className="w-4 h-4" />}
                  </div>
                  <div className="overflow-hidden">
                    <h4 className="text-xs font-bold text-white truncate">{place.name}</h4>
                    <p className="text-[10px] font-mono text-slate-400 truncate">
                      {place.coordinate.latitude.toFixed(5)}, {place.coordinate.longitude.toFixed(5)}
                    </p>
                  </div>
                </div>

                <div className="flex items-center gap-1.5">
                  <button
                    onClick={() => {
                      onTeleportTo(place.coordinate);
                      onClose();
                    }}
                    title="Teleport to this place"
                    className="px-2.5 py-1.5 rounded-xl bg-cyan-500/20 hover:bg-cyan-500 text-cyan-400 hover:text-white text-xs font-semibold transition-all flex items-center gap-1"
                  >
                    <Navigation className="w-3 h-3" />
                    <span>Go</span>
                  </button>
                  <button
                    onClick={() => onDeletePlace(place.id)}
                    title="Delete place"
                    className="p-1.5 rounded-lg text-slate-600 hover:text-rose-400 transition-colors"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
};
