const express = require('express');
const app = express();

app.use(express.json());

app.post('/alert', (req, res) => {
  console.log('\n🔔 ALERT RECEIVED:');
  console.log(JSON.stringify(req.body, null, 2));
  res.sendStatus(200);
});

app.post('/critical', (req, res) => {
  console.log('\n🚨 CRITICAL ALERT:');
  req.body.alerts.forEach(alert => {
    console.log(`❌ ${alert.labels.alertname}: ${alert.annotations.summary}`);
  });
  res.sendStatus(200);
});

app.post('/warning', (req, res) => {
  console.log('\n⚠️  WARNING ALERT:');
  req.body.alerts.forEach(alert => {
    console.log(`⚠️  ${alert.labels.alertname}: ${alert.annotations.summary}`);
  });
  res.sendStatus(200);
});

app.listen(5001, () => {
  console.log('Webhook receiver listening on port 5001');
});