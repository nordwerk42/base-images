const express = require('express');
const app = express();
const PORT = process.env.PORT || 8080;

app.get('/', async (req, res) => {
  // do an https request to test certificates and network
  try {
    await fetch('https://opencode.de');
    console.log('Fetch to https://opencode.de succeeded');
  } catch (err) {
    console.log(err);
  }
  res.json({ message: 'Hello from Express in a container!' });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server is running on port ${PORT}`);
});
