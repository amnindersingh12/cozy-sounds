import os

from model.lyrics2lofi_dataset import Lyrics2LofiDataset
from model.lyrics2lofi_model import Lyrics2LofiModel
from model.train import train

if __name__ == '__main__':
    dataset_folder = "model/dataset/processed-lyrics-spotify"
    if not os.path.isdir(dataset_folder):
        raise FileNotFoundError(f"Dataset folder not found: {dataset_folder}")
    dataset_files = os.listdir(dataset_folder)
    if not dataset_files:
        raise FileNotFoundError(f"Dataset folder is empty: {dataset_folder}")
    embeddings_file = "embeddings"  # without .npy extension
    embedding_lengths_file = "embedding_lengths.json"
    if not os.path.isfile(f"{embeddings_file}.npy"):
        raise FileNotFoundError(f"Embeddings file not found: {embeddings_file}.npy")
    if not os.path.isfile(embedding_lengths_file):
        raise FileNotFoundError(f"Embedding lengths file not found: {embedding_lengths_file}")

    max_epochs_env = os.environ.get("MAX_EPOCHS", "").strip()
    max_epochs = int(max_epochs_env) if max_epochs_env else None

    dataset = Lyrics2LofiDataset(dataset_folder, dataset_files, embeddings_file, embedding_lengths_file)
    model = Lyrics2LofiModel()

    train(dataset, model, "lyrics2lofi", max_epochs=max_epochs)
