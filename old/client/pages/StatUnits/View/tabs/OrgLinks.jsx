import React, { useState, useEffect } from 'react'
import { func, oneOfType, number, string, bool } from 'prop-types'
import Tree from 'antd/lib/tree'
import { Segment, Loader, Header } from 'semantic-ui-react'

import styles from './styles.scss'

/** IMPORTANT: Do not remove this import. It has to be added,
 ** otherwise we get a reference error in React when clicking on the Organization Links tab* */
import regeneratorRuntime from 'regenerator-runtime'

const hasChildren = node => node.orgLinksNodes && node.orgLinksNodes.length > 0

function OrgLinks({ id, fetchData, activeTab, localize, isDeletedUnit }) {
  const [orgLinksRoot, setOrgLinksRoot] = useState(undefined)

  useEffect(() => {
    const fetchOrgLinks = async () => {
      if (!isDeletedUnit) {
        const orgLinksRoot = await fetchData({ id })
        setOrgLinksRoot(orgLinksRoot)
      }
    }

    fetchOrgLinks()
  }, [id, fetchData, isDeletedUnit])

  const renderChildren = nodes =>
    nodes.map((node) => {
      const anyChild = hasChildren(node)
      return (
        <Tree.TreeNode uid={node.regId} key={node.regId} title={node.name} isLeaf={!anyChild}>
          {anyChild && renderChildren(node.orgLinksNodes)}
        </Tree.TreeNode>
      )
    })

  const highLight = node => node.props.uid === id

  return (
    <div>
      {activeTab !== 'orgLinks' && (
        <Header as="h5" className={styles.heigthHeader} content={localize('OrgLinks')} />
      )}
      <Segment>
        {!isDeletedUnit ? (
          orgLinksRoot ? (
            <Tree filterTreeNode={highLight} defaultExpandAll>
              <Tree.TreeNode
                uid={orgLinksRoot.regId}
                title={orgLinksRoot.name}
                key={orgLinksRoot.regId}
              >
                {hasChildren(orgLinksRoot) && renderChildren(orgLinksRoot.orgLinksNodes)}
              </Tree.TreeNode>
            </Tree>
          ) : (
            <Loader active />
          )
        ) : (
          <Header size="small" content={localize('OrgLinksNotFound')} textAlign="center" />
        )}
      </Segment>
    </div>
  )
}

OrgLinks.propTypes = {
  id: oneOfType([number, string]).isRequired,
  fetchData: func.isRequired,
  activeTab: string.isRequired,
  localize: func.isRequired,
  isDeletedUnit: bool.isRequired,
}

export default OrgLinks
