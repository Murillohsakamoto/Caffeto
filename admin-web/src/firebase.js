import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { getStorage } from 'firebase/storage';
import { getFunctions, httpsCallable } from 'firebase/functions';

const firebaseConfig = {
  apiKey: 'AIzaSyCB_gIwQKwlprhCvc9fEK0BSiiAu0f-jnA',
  authDomain: 'caffeto-a12fe.firebaseapp.com',
  projectId: 'caffeto-a12fe',
  storageBucket: 'caffeto-a12fe.firebasestorage.app',
  messagingSenderId: '792481109924',
  appId: '1:792481109924:web:1c1551dac19ff1a77bd331',
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app, 'caffeto');
export const storage = getStorage(app);
export const functions = getFunctions(app, 'southamerica-east1');

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result.split(',')[1]);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

/**
 * Sobe a foto de um produto/combo do cardápio pela Cloud Function
 * atualizarImagemCardapio (Admin SDK) — upload direto pro Storage não
 * funciona pra esse caminho, as regras exigem checar admin no Firestore
 * (banco nomeado "caffeto", que Storage Rules não enxerga).
 */
export async function atualizarImagemCardapio(itemId, file) {
  const imagemBase64 = await fileToBase64(file);
  const call = httpsCallable(functions, 'atualizarImagemCardapio');
  const { data } = await call({ itemId, imagemBase64 });
  return data.url;
}
