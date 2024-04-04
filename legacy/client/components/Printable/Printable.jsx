import React, { useRef } from 'react'
import { node, bool, string } from 'prop-types'
import ReactToPrint from 'react-to-print'

import getUid from 'helpers/getUid.js'
import styles from './styles.scss'

const Printable = ({ children, btnPrint, btnShowCondition }) => {
  const printContainerId = useRef(`printContainer${getUid()}`)
  const content = useRef(null)

  return (
    <div>
      <div id={printContainerId.current} className={styles.printStyle} ref={content}>
        {children}
      </div>
      <br />
      {btnShowCondition && (
        <ReactToPrint trigger={() => btnPrint} content={() => content.current} />
      )}
      <br />
      <br />
    </div>
  )
}

Printable.propTypes = {
  children: node.isRequired,
  btnShowCondition: bool,
  btnPrint: node.isRequired,
}

Printable.defaultProps = {
  btnShowCondition: true,
}

export default Printable
