import React from 'react'
import { Link } from 'react-router'
import { Breadcrumb } from 'semantic-ui-react'


const sections = (routes) => {
  const modified = routes

  if (modified[modified.length - 1].path === undefined) { modified.pop() }


  return modified.reduce((previousValue, currentValue, index, array) => ({
    key: currentValue.path,
    content: previousValue.path + currentValue.path,
    // link: index !== modified.length - 1,
    //as: Link,
    // to: currentValue.path,
  }), [],
  )
}

export default ({ routes }) => (
  <Breadcrumb icon="right angle" sections={sections(routes)} />
)
