import React from 'react'
import { IndexLink, Link } from 'react-router'

export default props => (
  <div>
    <IndexLink to="/">Home</IndexLink>
    {' | '}
    <Link to="/about">About</Link>
    <br />
    {props.children}
  </div>
)
