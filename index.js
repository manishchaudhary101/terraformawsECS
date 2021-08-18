const express = require('express')
const app = express()
const port = process.env.PORT || 5001 ;

app.get('/', (req, res) => {
    res.send('Dockerised app running on ECS using Terraform')
  })

app.listen(port, () => {
  console.log(`Example app listening at http://localhost:${port}`)
})