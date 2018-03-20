import React from 'react'
import { shape } from 'prop-types'

const RegionList = ({ rowData: { regions } }) => <div>{regions.join(', ')}</div>

RegionList.propTypes = {
  rowData: shape().isRequired,
}

export default RegionList
