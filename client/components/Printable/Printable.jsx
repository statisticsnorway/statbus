import React from 'react'
import { node, bool, string } from 'prop-types'
import ReactToPrint from 'react-to-print'

import getUid from 'helpers/getUid'
import styles from './styles.pcss'

const Printable = ({ printContainerId, children, btnPrint, btnShowCondition }) => {
  const content = document.getElementById(printContainerId)
  return (
    <div>
      <div id={printContainerId} className={styles.printStyle}>
        {children}
      </div>
      <br />
      {// eslint-disable-next-line jsx-a11y/no-static-element-interactions
      btnShowCondition && <ReactToPrint trigger={() => btnPrint} content={() => content} />}
      <br />
      <br />
    </div>
  )
}

Printable.propTypes = {
  children: node.isRequired,
  btnShowCondition: bool,
  btnPrint: node.isRequired,
  printContainerId: string,
}

Printable.defaultProps = {
  btnShowCondition: true,
  printContainerId: `printContainer${getUid()}`,
}

export default Printable
