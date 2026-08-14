import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';

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
